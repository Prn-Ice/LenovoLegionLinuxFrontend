// Tests for the package power sampler. A temporary sysfs tree supplies known
// energy values, including a counter wrap and a changed range.
#include "package_power_sampler.h"

#include <ftw.h>
#include <glib.h>

#include <string>

namespace {

int RemovePath(const char *path, const struct stat *, int, struct FTW *) {
  return remove(path);
}

void RemoveTree(const std::string &path) {
  nftw(path.c_str(), RemovePath, 16, FTW_DEPTH | FTW_PHYS);
}

void WriteFile(const std::string &path, const std::string &value) {
  GError *error = nullptr;
  g_file_set_contents(path.c_str(), value.c_str(), value.size(), &error);
  g_assert_no_error(error);
}

std::string CreateRoot() {
  GError *error = nullptr;
  gchar *path = g_dir_make_tmp("legion-telemetry-test-XXXXXX", &error);
  g_assert_no_error(error);
  g_assert_nonnull(path);
  std::string result(path);
  g_free(path);
  return result;
}

std::string CreateDomain(const std::string &root, const std::string &entry,
                         const std::string &name, std::uint64_t energy_uj,
                         std::uint64_t range_uj) {
  const std::string path = root + "/" + entry;
  g_assert_cmpint(g_mkdir_with_parents(path.c_str(), 0700), ==, 0);
  WriteFile(path + "/name", name);
  WriteFile(path + "/energy_uj", std::to_string(energy_uj));
  WriteFile(path + "/max_energy_range_uj", std::to_string(range_uj));
  return path;
}

void TestNormalDelta() {
  const auto root = CreateRoot();
  const auto package =
      CreateDomain(root, "intel-rapl:0", "package-0", 1000000, 10000000);
  CreateDomain(root, "intel-rapl:0:0", "core", 500000, 10000000);
  PackagePowerSampler sampler(root);

  sampler.Sample(1000000);
  g_assert_false(sampler.reading().available);
  WriteFile(package + "/energy_uj", "3000000");
  sampler.Sample(2000000);

  g_assert_true(sampler.reading().available);
  g_assert_cmpfloat_with_epsilon(sampler.reading().watts, 2.0, 0.0001);
  g_assert_cmpstr(sampler.reading().domain.c_str(), ==, "package-0");
  RemoveTree(root);
}

void TestCounterWrap() {
  const auto root = CreateRoot();
  const auto package =
      CreateDomain(root, "intel-rapl:0", "package-0", 9000000, 10000000);
  PackagePowerSampler sampler(root);

  sampler.Sample(1000000);
  WriteFile(package + "/energy_uj", "1000000");
  sampler.Sample(2000000);

  g_assert_true(sampler.reading().available);
  g_assert_cmpfloat_with_epsilon(sampler.reading().watts, 2.0, 0.0001);
  RemoveTree(root);
}

void TestMissingInterface() {
  const auto root = CreateRoot();
  PackagePowerSampler sampler(root);

  sampler.Sample(1000000);

  g_assert_false(sampler.reading().available);
  g_assert_cmpstr(sampler.reading().domain.c_str(), ==, "");
  RemoveTree(root);
}

void TestRangeChangeResetsBaseline() {
  const auto root = CreateRoot();
  const auto package =
      CreateDomain(root, "intel-rapl:0", "package-0", 1000000, 10000000);
  PackagePowerSampler sampler(root);

  sampler.Sample(1000000);
  WriteFile(package + "/energy_uj", "2000000");
  WriteFile(package + "/max_energy_range_uj", "20000000");
  sampler.Sample(2000000);

  g_assert_false(sampler.reading().available);
  WriteFile(package + "/energy_uj", "4000000");
  sampler.Sample(3000000);
  g_assert_true(sampler.reading().available);
  g_assert_cmpfloat_with_epsilon(sampler.reading().watts, 2.0, 0.0001);
  RemoveTree(root);
}

}  // namespace

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/package-power/normal-delta", TestNormalDelta);
  g_test_add_func("/package-power/counter-wrap", TestCounterWrap);
  g_test_add_func("/package-power/missing-interface", TestMissingInterface);
  g_test_add_func("/package-power/range-change", TestRangeChangeResetsBaseline);
  return g_test_run();
}
