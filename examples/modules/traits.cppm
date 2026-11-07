export module example.traits;

import example.theme;

export namespace ui {
template<class T>
struct ViewTraits;

template<class T>
int render(const T& view) {
    return ViewTraits<T>::render(view) + renderOffset();
}
}
