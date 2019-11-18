defmodule B do
  import B.Gettext

  def hello do
    gettext("Hi from B")
    |> IO.puts()
  end

  def items(n) do
    dngettext("items", "%{count} item", "%{count} items", n)
  end

  def one do
    gettext("One")
  end
end
