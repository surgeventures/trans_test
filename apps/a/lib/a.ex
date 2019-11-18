defmodule A do
  import A.Gettext

  def hello do
    gettext("Hello!")
    |> IO.puts()
  end

  def one do
    gettext("One")
  end
end
