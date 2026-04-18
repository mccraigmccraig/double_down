defmodule DoubleDown.BehaviourFacade.CompileHelper do
  @moduledoc false

  # Helper for ensuring behaviour modules are compiled and their .beam
  # files are on disk before BehaviourFacade facades that depend on them.
  #
  # This is only needed when the behaviour and facade are compiled in the
  # same batch (e.g. both in test/support/). In normal usage the behaviour
  # would be in lib/ or a dependency, compiled in a prior batch.

  @doc false
  @spec ensure_compiled!(Path.t()) :: :ok
  def ensure_compiled!(source_path) do
    # Compile the file — returns [{module, binary}, ...]
    compiled = Code.compile_file(source_path)

    # Write each beam binary to the build output directory so
    # Code.Typespec.fetch_callbacks/1 can find them.
    for {module, binary} <- compiled do
      beam_path = beam_output_path(module)
      File.mkdir_p!(Path.dirname(beam_path))
      File.write!(beam_path, binary)
      # Load the binary so the code server also has it
      :code.load_binary(module, String.to_charlist(beam_path), binary)
    end

    :ok
  end

  defp beam_output_path(module) do
    # Use the first code path entry that looks like a build directory
    ebin_dir =
      :code.get_path()
      |> Enum.map(&to_string/1)
      |> Enum.find(&String.contains?(&1, "_build"))

    if ebin_dir do
      Path.join(ebin_dir, "#{module}.beam")
    else
      # Fallback: write to a temp directory and add it to the code path
      tmp = Path.join(System.tmp_dir!(), "double_down_beams")
      File.mkdir_p!(tmp)
      :code.add_patha(String.to_charlist(tmp))
      Path.join(tmp, "#{module}.beam")
    end
  end
end
