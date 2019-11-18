defmodule A do
  import A.Gettext

  def hello do
    gettext("Hello!")
    |> IO.puts()
  end

  def f2 do
    gettext("I come from feature 2!")

  def one do
    gettext("One")
  end
end
