defmodule DoubleDownTest do
  use ExUnit.Case, async: true

  test "DoubleDown.Contract module exists" do
    assert Code.ensure_loaded?(DoubleDown.Contract)
  end

  test "DoubleDown.Dispatch module exists" do
    assert Code.ensure_loaded?(DoubleDown.Dispatch)
  end

  test "DoubleDown.Testing module exists" do
    assert Code.ensure_loaded?(DoubleDown.Testing)
  end

  test "README.md version matches VERSION" do
    %{major: major, minor: minor} =
      "VERSION"
      |> File.read!()
      |> String.trim()
      |> Version.parse!()

    readme = File.read!("README.md")
    expected = "~> #{major}.#{minor}"

    assert String.contains?(readme, "{:double_down, \"#{expected}\""),
           "README.md does not contain the current version. " <>
             "Update the installation snippet to use the version from the VERSION file."
  end
end
