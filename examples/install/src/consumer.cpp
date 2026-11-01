#include <lib/lib.hpp>
#include <print>

#if !defined(INSTALL_API_VERSION) || INSTALL_API_VERSION != 1
#error "The installed library must propagate its public definitions"
#endif

#ifdef INSTALL_IMPLEMENTATION
#error "The installed library must not propagate private definitions"
#endif

int main() { std::println("external lib: {}", lib::go()); }
