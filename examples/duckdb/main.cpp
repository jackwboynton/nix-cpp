#include <duckdb.hpp>
#include <iostream>

int main() {
  duckdb::DuckDB db(nullptr);
  duckdb::Connection connection(db);

  auto result = connection.Query("SELECT 21 * 2 AS answer");

  if (result->HasError()) {
    std::cerr << "error: " << result->GetError() << "\n";
    return 1;
  }

  std::cout << result->GetValue(0, 0).ToString() << "\n";
}
