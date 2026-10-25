
#include <arrow/api.h>

#include <memory>
#include <print>

int main() {
  arrow::Int32Builder builder;

  if (auto status = builder.AppendValues({10, 20, 30}); !status.ok()) {
    std::println("error: {}", status.ToString());
    return 1;
  }

  std::shared_ptr<arrow::Array> array;

  if (auto status = builder.Finish(&array); !status.ok()) {
    std::println("error: {}", status.ToString());
    return 1;
  }

  std::println("Arrow array length: {}", array->length());
}
