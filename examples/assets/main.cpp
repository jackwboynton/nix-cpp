#include <filesystem>
#include <fstream>
#include <iostream>
#include <system_error>
#include <vector>

#if !defined(__APPLE__) && !defined(__linux__)
#error "Executable path lookup is only implemented for macOS and Linux"
#endif

#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

std::filesystem::path executablePath(std::error_code& error) {
#ifdef __APPLE__
  uint32_t size = 0;
  _NSGetExecutablePath(nullptr, &size);
  std::vector<char> buffer(size);
  if (_NSGetExecutablePath(buffer.data(), &size) != 0) {
    error = std::make_error_code(std::errc::filename_too_long);
    return {};
  }
  return std::filesystem::canonical(buffer.data(), error);
#else
  return std::filesystem::canonical("/proc/self/exe", error);
#endif
}

int main() {
  std::error_code error;
  const auto executable = executablePath(error);
  if (error) {
    std::cerr << "Could not locate executable: " << error.message() << '\n';
    return 1;
  }

  std::ifstream asset(executable.parent_path() / "assets/test.txt");
  if (!asset) {
    std::cerr << "Could not open assets/test.txt\n";
    return 1;
  }

  std::cout << asset.rdbuf();
  return asset.bad() ? 1 : 0;
}
