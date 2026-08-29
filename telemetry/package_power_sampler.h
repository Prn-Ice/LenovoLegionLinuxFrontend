#pragma once

#include <cstdint>
#include <string>

struct PackagePowerReading {
  bool available = false;
  double watts = 0.0;
  std::string domain;
  std::string error;
};

class PackagePowerSampler {
 public:
  explicit PackagePowerSampler(std::string powercap_root);

  void Sample(std::int64_t monotonic_microseconds);
  const PackagePowerReading& reading() const;

 private:
  bool DiscoverPackageDomain();
  void ResetBaseline();
  void SetUnavailable(const std::string& error);

  static bool ReadText(const std::string& path, std::string* value);
  static bool ReadUint64(const std::string& path, std::uint64_t* value);

  std::string powercap_root_;
  std::string domain_path_;
  std::string domain_name_;
  bool has_previous_sample_ = false;
  std::uint64_t previous_energy_uj_ = 0;
  std::uint64_t previous_range_uj_ = 0;
  std::int64_t previous_time_us_ = 0;
  PackagePowerReading reading_;
};
