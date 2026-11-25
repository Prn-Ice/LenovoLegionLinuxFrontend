// Samples CPU package power from the Linux powercap interface.
//
// The kernel exposes a monotonic energy counter in microjoules. Power is the
// energy change divided by the elapsed time: 1 µJ / 1 µs = 1 W. Counters can
// wrap at max_energy_range_uj, so a smaller new value is handled as a wrap.
// The sampler reports why a value is unavailable instead of guessing.
#include "package_power_sampler.h"

#include <dirent.h>

#include <algorithm>
#include <cerrno>
#include <cstdlib>
#include <fstream>
#include <limits>
#include <sstream>
#include <utility>
#include <vector>

namespace {

// Reject samples that are too close together (noisy) or too far apart
// (a suspended or stalled service). 100 ms to 10 s is a useful range.
constexpr std::int64_t kMinimumSampleIntervalUs = 100000;
constexpr std::int64_t kMaximumSampleIntervalUs = 10000000;
// A desktop CPU package above this value is more likely a bad reading than
// real hardware behavior.
constexpr double kMaximumPlausiblePackageWatts = 1000.0;

// Remove surrounding whitespace from a sysfs value.
std::string Trim(std::string value) {
  const auto first = value.find_first_not_of(" \t\r\n");
  if (first == std::string::npos)
    return {};
  const auto last = value.find_last_not_of(" \t\r\n");
  return value.substr(first, last - first + 1);
}

}  // namespace

PackagePowerSampler::PackagePowerSampler(std::string powercap_root)
    : powercap_root_(std::move(powercap_root)) {}

void PackagePowerSampler::Sample(std::int64_t monotonic_microseconds) {
  // Find a package domain once. If discovery fails, keep reporting why.
  if (domain_path_.empty() && !DiscoverPackageDomain()) {
    SetUnavailable("CPU package energy is unavailable");
    return;
  }

  std::uint64_t energy_uj = 0;
  std::uint64_t range_uj = 0;
  if (!ReadUint64(domain_path_ + "/energy_uj", &energy_uj) ||
      !ReadUint64(domain_path_ + "/max_energy_range_uj", &range_uj) ||
      range_uj == 0 || energy_uj > range_uj) {
    // The domain disappeared or changed shape. Rediscover on the next call.
    domain_path_.clear();
    domain_name_.clear();
    ResetBaseline();
    SetUnavailable("CPU package energy could not be read");
    return;
  }

  // The first sample only establishes a baseline. A changed counter range
  // also invalidates the previous baseline.
  if (!has_previous_sample_ || range_uj != previous_range_uj_) {
    previous_energy_uj_ = energy_uj;
    previous_range_uj_ = range_uj;
    previous_time_us_ = monotonic_microseconds;
    has_previous_sample_ = true;
    SetUnavailable("Collecting the initial package power sample");
    return;
  }

  const auto elapsed_us = monotonic_microseconds - previous_time_us_;
  if (elapsed_us < kMinimumSampleIntervalUs ||
      elapsed_us > kMaximumSampleIntervalUs) {
    previous_energy_uj_ = energy_uj;
    previous_range_uj_ = range_uj;
    previous_time_us_ = monotonic_microseconds;
    SetUnavailable("Package power sample interval was invalid");
    return;
  }

  // Handle counter wrap: if energy went down, add the distance to the top of
  // the range before adding the new value.
  const std::uint64_t delta_uj =
      energy_uj >= previous_energy_uj_
          ? energy_uj - previous_energy_uj_
          : (range_uj - previous_energy_uj_) + energy_uj;
  const double watts =
      static_cast<double>(delta_uj) / static_cast<double>(elapsed_us);

  previous_energy_uj_ = energy_uj;
  previous_range_uj_ = range_uj;
  previous_time_us_ = monotonic_microseconds;

  if (watts < 0.0 || watts > kMaximumPlausiblePackageWatts) {
    SetUnavailable("Package power sample was outside the supported range");
    return;
  }

  reading_.available = true;
  reading_.watts = watts;
  reading_.domain = domain_name_;
  reading_.error.clear();
}

const PackagePowerReading &PackagePowerSampler::reading() const {
  return reading_;
}

// Look for a powercap zone whose name starts with "package-" and whose energy
// files are readable. Sorting makes the choice stable when several packages
// exist.
bool PackagePowerSampler::DiscoverPackageDomain() {
  DIR *directory = opendir(powercap_root_.c_str());
  if (directory == nullptr)
    return false;

  std::vector<std::string> candidates;
  while (const auto *entry = readdir(directory)) {
    if (entry->d_name[0] == '.')
      continue;
    const std::string path = powercap_root_ + "/" + entry->d_name;
    std::string name;
    if (ReadText(path + "/name", &name) && name.rfind("package-", 0) == 0) {
      candidates.push_back(path);
    }
  }
  closedir(directory);

  std::sort(candidates.begin(), candidates.end());
  for (const auto &path : candidates) {
    std::string name;
    std::uint64_t energy_uj = 0;
    std::uint64_t range_uj = 0;
    if (ReadText(path + "/name", &name) &&
        ReadUint64(path + "/energy_uj", &energy_uj) &&
        ReadUint64(path + "/max_energy_range_uj", &range_uj) && range_uj > 0) {
      domain_path_ = path;
      domain_name_ = name;
      ResetBaseline();
      return true;
    }
  }
  return false;
}

void PackagePowerSampler::ResetBaseline() {
  has_previous_sample_ = false;
  previous_energy_uj_ = 0;
  previous_range_uj_ = 0;
  previous_time_us_ = 0;
}

void PackagePowerSampler::SetUnavailable(const std::string &error) {
  reading_.available = false;
  reading_.watts = 0.0;
  reading_.domain = domain_name_;
  reading_.error = error;
}

// Read a whole sysfs file. sysfs files are small, so reading to the end is
// fine; the stream state catches I/O errors.
bool PackagePowerSampler::ReadText(const std::string &path,
                                   std::string *value) {
  std::ifstream stream(path);
  if (!stream)
    return false;
  std::ostringstream contents;
  contents << stream.rdbuf();
  if (stream.bad())
    return false;
  *value = Trim(contents.str());
  return !value->empty();
}

// Parse an unsigned decimal value and reject trailing text or overflow.
bool PackagePowerSampler::ReadUint64(const std::string &path,
                                     std::uint64_t *value) {
  std::string raw;
  if (!ReadText(path, &raw))
    return false;

  errno = 0;
  char *end = nullptr;
  const auto parsed = std::strtoull(raw.c_str(), &end, 10);
  if (errno != 0 || end == raw.c_str() || *end != '\0' ||
      parsed > std::numeric_limits<std::uint64_t>::max()) {
    return false;
  }
  *value = static_cast<std::uint64_t>(parsed);
  return true;
}
