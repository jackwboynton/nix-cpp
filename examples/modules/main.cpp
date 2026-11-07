import example.ui;

struct Plot { int value; };

template<>
struct ui::ViewTraits<Plot> {
    static int render(const Plot& plot) { return plot.value; }
};

int main() {
    return ui::render(Plot{40}) == 42 ? 0 : 1;
}
