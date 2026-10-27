#include "math.hpp"
#include <cassert>

#ifndef MATH_PRIVATE
#error "Library tests should inherit private definitions"
#endif

int main() { assert(add(20, 22) == 42); }
