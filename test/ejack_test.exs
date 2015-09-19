defmodule EJackTest do
  use ExUnit.Case, async: true

  test "the truth" do
    assert 1 + 1 == 2
  end

  test "async test" do 
    {:ok, thing} = EJack.Asy.start_link
    assert EJack.Asy.get(thing, "not_in_it") == nil
    EJack.Asy.put(thing, "not_in_it", 3)
    assert EJack.Asy.get(thing, "not_in_it") == 3
  end
end
