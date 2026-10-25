#include "math.hpp"
#include <print>

#ifndef MATH_PUBLIC
#error "Public definition was not propagated"
#endif

#ifdef MATH_PRIVATE
#error "Private definition leaked into dependent target"
#endif

int main() { std::println("add(20, 22) = {}", add(20, 22)); }
