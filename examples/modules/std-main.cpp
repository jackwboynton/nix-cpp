import std;

int main() {
    std::vector<int> values{1, 2, 3};
    if (std::format("{}", std::accumulate(values.begin(), values.end(), 0)) != "6") {
        return 1;
    }
    int sum = 0;
    for (auto [a, b] : std::views::zip(values, values)) {
        sum += a * b;
    }
    return sum == 14 ? 0 : 1;
}
