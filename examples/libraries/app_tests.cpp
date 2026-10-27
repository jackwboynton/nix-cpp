#include "math.hpp"
#include <cassert>

#ifndef MATH_PUBLIC
#error "Executable tests should inherit dependency definitions"
#endif

#ifdef MATH_PRIVATE
#error "Dependency private definitions should not leak into executable tests"
#endif

int main() { assert(add(20, 22) == 42); }
