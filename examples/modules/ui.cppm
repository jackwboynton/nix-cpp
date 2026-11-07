export module example.ui;

export namespace ui {
template<class T>
struct ViewTraits;

int renderOffset() { return 2; }

template<class T>
int render(const T& view) {
    return ViewTraits<T>::render(view) + renderOffset();
}
}
