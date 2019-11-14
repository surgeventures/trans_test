defmodule A do
  import A.Gettext

  def hello do
    gettext("Hello!")
    |> IO.puts()
  end
end
