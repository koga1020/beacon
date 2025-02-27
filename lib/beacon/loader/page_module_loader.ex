defmodule Beacon.Loader.PageModuleLoader do
  alias Beacon.Loader.ModuleLoader
  alias Beacon.Pages.Page
  alias Beacon.Pages.PageEvent
  alias Beacon.Pages.PageHelper
  require Logger

  def load_templates(site, pages) do
    page_module = Beacon.Loader.page_module_for_site(site)
    component_module = Beacon.Loader.component_module_for_site(site)

    # Group function heads together to avoid compiler warnings
    functions = [
      for fun <- [
            &page_assigns/1,
            &handle_event/1,
            &helper/1
          ],
          page <- pages do
        fun.(page)
      end,
      dynamic_helper()
    ]

    ast = render(page_module, component_module, functions)

    Enum.each(pages, fn page -> store_page(page, page_module, component_module) end)

    :ok = ModuleLoader.load(page_module, ast)
    {:ok, ast}
  end

  defp render(module_name, component_module, functions) do
    quote do
      defmodule unquote(module_name) do
        use Phoenix.HTML
        import Phoenix.Component
        unquote(ModuleLoader.maybe_import_my_component(component_module, functions))

        unquote_splicing(functions)
      end
    end
  end

  defp store_page(%Page{} = page, page_module, component_module) do
    %{id: page_id, layout_id: layout_id, site: site, path: path, template: template} = page

    Beacon.safe_code_heex_check!(site, template)

    template_ast =
      EEx.compile_string(template,
        engine: Phoenix.LiveView.HTMLEngine,
        line: 1,
        trim: true,
        caller: __ENV__,
        source: template,
        file: "page-render-#{page_id}"
      )

    Beacon.Router.add_page(site, path, {page_id, layout_id, template_ast, page_module, component_module})
  end

  defp page_assigns(%Page{} = page) do
    %{id: id, meta_tags: meta_tags, title: title} = page

    meta_tags =
      if meta_tags do
        Enum.map(meta_tags, &interpolate_meta_tag(&1, page))
      end

    quote do
      def page_assigns(unquote(id)) do
        %{
          title: unquote(title),
          meta_tags: unquote(Macro.escape(meta_tags))
        }
      end
    end
  end

  # Replace meta tag attribute value strings like "%title%" with "#{page.title}"
  defp interpolate_meta_tag(meta_tag, page) when is_map(meta_tag) do
    Map.new(meta_tag, &interpolate_meta_tag_attribute(&1, page))
  end

  defp interpolate_meta_tag_attribute({key, value}, page) when is_binary(value) do
    new_value =
      Enum.reduce(Page.meta_tag_interpolation_keys(), value, fn key, value ->
        page_value = page |> Map.get(key) |> to_string()
        String.replace(value, "%#{key}%", page_value)
      end)

    {key, new_value}
  end

  # TODO: path_to_args in paths with dynamic segments may be broken
  defp handle_event(%Page{site: site, path: path, events: events}) do
    Enum.map(events, fn %PageEvent{} = event ->
      Beacon.safe_code_check!(site, event.code)

      quote do
        def handle_event(unquote(path_to_args(path, "")), unquote(event.event_name), var!(event_params), var!(socket)) do
          unquote(Code.string_to_quoted!(event.code))
        end
      end
    end)
  end

  # TODO: validate fn name and args
  def helper(%Page{site: site, helpers: helpers}) do
    Enum.map(helpers, fn %PageHelper{} = helper ->
      Beacon.safe_code_check!(site, helper.code)

      args = Code.string_to_quoted!(helper.helper_args)

      quote do
        def unquote(String.to_atom(helper.helper_name))(unquote(args)) do
          unquote(Code.string_to_quoted!(helper.code))
        end
      end
    end)
  end

  defp dynamic_helper do
    quote do
      def dynamic_helper(helper_name, args) do
        Beacon.Loader.call_function_with_retry(__MODULE__, String.to_atom(helper_name), [args])
      end
    end
  end

  defp path_to_args("", _), do: []

  defp path_to_args(path, prefix) do
    path
    |> String.split("/")
    |> Enum.map(&path_segment_to_arg(&1, prefix))

    # |> String.replace(",|", " |")
  end

  defp path_segment_to_arg(":" <> segment, prefix), do: prefix <> segment
  defp path_segment_to_arg("*" <> segment, prefix), do: "| " <> prefix <> segment
  defp path_segment_to_arg(segment, _prefix), do: segment
end
