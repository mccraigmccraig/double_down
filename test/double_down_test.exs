defmodule DoubleDownTest do
  use ExUnit.Case, async: true

  test "DoubleDown.Contract module exists" do
    assert Code.ensure_loaded?(DoubleDown.Contract)
  end

  test "DoubleDown.Contract.Dispatch module exists" do
    assert Code.ensure_loaded?(DoubleDown.Contract.Dispatch)
  end

  test "DoubleDown.Testing module exists" do
    assert Code.ensure_loaded?(DoubleDown.Testing)
  end
end
