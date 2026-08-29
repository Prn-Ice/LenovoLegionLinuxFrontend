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

constexpr std::int64_t kMinimumSampleIntervalUs = 100000;
constexpr std::int64_t kMaximumSampleIntervalUs = 10000000;
constexpr double kMaximumPlausiblePackageWatts = 1000.0;

std::string Trim(std::string value) {
  const auto first = value.find_first_not_of(" \t\r\n");
  if (first == std::string::npos) return {};
  const auto last = value.find_last_not_of(" \t\r\n");
  return value.substr(first, last - first + 1);
}

}  // namespace

PackagePowerSampler::PackagePowerSampler(std::string powercap_root)
    : powercap_root_(std::move(powercap_root)) {}

void PackagePowerSampler::Sample(std::int64_t monotonic_microseconds) {
  if (domain_path_.empty() && !DiscoverPackageDomain()) {
    SetUnavailable("CPU package energy is unavailable");
    return;
  }

  std::uint64_t energy_uj = 0;
  std::uint64_t range_uj = 0;
  if (!ReadUint64(domain_path_ + "/energy_uj", &energy_uj) ||
      !ReadUint64(domain_path_ + "/max_energy_range_uj", &range_uj) ||
      range_uj == 0 || energy_uj > range_uj) {
    domain_path_.clear();
    domain_name_.clear();
    ResetBaseline();
    SetUnavailable("CPU package energy could not be read");
    return;
  }

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

  const std::uint64_t delta_uj = energy_uj >= previous_energy_uj_
                                     ? energy_uj - previous_energy_uj_
                                     : (range_uj - previous_energy_uj_) +
                                           energy_uj;
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

const PackagePowerReading& PackagePowerSampler::reading() const {
  return reading_;
}

bool PackagePowerSampler::DiscoverPackageDomain() {
  DIR* directory = opendir(powercap_root_.c_str());
  if (directory == nullptr) return false;

  std::vector<std::string> candidates;
  while (const auto* entry = readdir(directory)) {
    if (entry->d_name[0] == '.') continue;
    const std::string path = powercap_root_ + "/" + entry->d_name;
    std::string name;
    if (ReadText(path + "/name", &name) && name.rfind("package-", 0) == 0) {
      candidates.push_back(path);
    }
  }
  closedir(directory);

  std::sort(candidates.begin(), candidates.end());
  for (const auto& path : candidates) {
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

void PackagePowerSampler::SetUnavailable(const std::string& error) {
  reading_.available = false;
  reading_.watts = 0.0;
  reading_.domain = domain_name_;
  reading_.error = error;
}

bool PackagePowerSampler::ReadText(const std::string& path,
                                   std::string* value) {
  std::ifstream stream(path);
  if (!stream) return false;
  std::ostringstream contents;
  contents << stream.rdbuf();
  if (stream.bad()) return false;
  *value = Trim(contents.str());
  return !value->empty();
}

bool PackagePowerSampler::ReadUint64(const std::string& path,
                                     std::uint64_t* value) {
  std::string raw;
  if (!ReadText(path, &raw)) return false;

  errno = 0;
  char* end = nullptr;
  const auto parsed = std::strtoull(raw.c_str(), &end, 10);
  if (errno != 0 || end == raw.c_str() || *end != '\0' ||
      parsed > std::numeric_limits<std::uint64_t>::max()) {
    return false;
  }
  *value = static_cast<std::uint64_t>(parsed);
  return true;
}
