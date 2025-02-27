defmodule Beacon.Pages do
  @moduledoc """
  The Pages context.
  """

  import Ecto.Query, warn: false
  alias Beacon.Repo

  alias Beacon.Loader.DBLoader
  alias Beacon.Pages.Page
  alias Beacon.Pages.PageEvent
  alias Beacon.Pages.PageHelper
  alias Beacon.Pages.PageVersion

  @doc """
  Returns the list of pages.

  ## Examples

      iex> list_pages()
      [%Page{}, ...]

  """
  def list_pages(preloads \\ []) do
    Page |> order_by(:order) |> Repo.all() |> Repo.preload(preloads)
  end

  def list_pages_for_site(site, preloads \\ []) do
    Repo.all(
      from p in Page,
        where: p.site == ^site,
        preload: ^preloads,
        order_by: [asc: p.order, asc: fragment("length(?)", p.path)]
    )
  end

  @doc """
  Returns a list of all pages for a given site that match the search query.

  The search is for a case-insensitive substring within the page path.
  """
  def search_for_site_pages(site, search_query, preloads \\ []) do
    Repo.all(
      from p in Page,
        where: p.site == ^site,
        where: ilike(p.path, ^"%#{search_query}%"),
        preload: ^preloads,
        order_by: [asc: p.order, asc: p.path]
    )
  end

  @doc """
  List all page templates for a layout.
  """
  def list_page_templates_by_layout(layout_id) do
    Repo.all(from p in Page, where: p.layout_id == ^layout_id, select: p.template)
  end

  @doc """
  Gets a single page.

  Raises `Ecto.NoResultsError` if the Page does not exist.

  ## Examples

      iex> get_page!(123)
      %Page{}

      iex> get_page!(456)
      ** (Ecto.NoResultsError)

  """
  def get_page!(id, preloads \\ []), do: Page |> Repo.get!(id) |> Repo.preload(preloads)

  @doc """
  Creates a page.

  ## Examples

      iex> create_page(%{field: value})
      {:ok, %Page{}}

      iex> create_page(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_page(attrs \\ %{}) do
    Repo.transaction(fn ->
      page_changeset =
        attrs
        |> Page.changeset()

      with {:ok, page} <- Repo.insert(page_changeset),
           {:ok, _page_version} <- create_version_for_page(page) do
        unless Map.get(attrs, :skip_reload, false) do
          DBLoader.load_from_db()
        end

        page
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def create_page!(attrs \\ %{}) do
    case create_page(attrs) do
      {:ok, page} -> page
      {:error, changeset} -> raise "Failed to create page #{inspect(changeset.errors)} "
    end
  end

  @doc """
  Updates a page and creates a page_version for the previously current page.

  ## Examples

      iex> update_page(page, %{field: new_value})
      {:ok, %Page{}}

      iex> update_page(page, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def publish_page(%Page{} = page) do
    Repo.transaction(fn ->
      page_changeset =
        Page.changeset(page, %{
          template: page.pending_template,
          layout_id: page.layout_id,
          version: page.version + 1
        })

      with {:ok, page} <- Repo.update(page_changeset),
           {:ok, _} <- create_version_for_page(page) do
        DBLoader.load_from_db()
        page
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def update_page_pending(%Page{} = page, template, layout_id, extra \\ %{}) do
    params =
      Map.merge(extra, %{
        "pending_template" => template,
        "pending_layout_id" => layout_id
      })

    page
    |> Page.update_pending_changeset(params)
    |> Repo.update()
  end

  @doc """
  Deletes a page.

  ## Examples

      iex> delete_page(page)
      {:ok, %Page{}}

      iex> delete_page(page)
      {:error, %Ecto.Changeset{}}

  """
  def delete_page(%Page{} = page) do
    case Repo.delete(page) do
      {:ok, _} ->
        DBLoader.load_from_db()
        {:ok, page}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking page changes.

  ## Examples

      iex> change_page(page)
      %Ecto.Changeset{data: %Page{}}

  """
  def change_page(%Page{} = page, attrs \\ %{}) do
    Page.changeset(page, attrs)
  end

  alias Beacon.Pages.PageVersion

  @doc """
  Returns the list of page_versions.

  ## Examples

      iex> list_page_versions()
      [%PageVersion{}, ...]

  """
  def list_page_versions do
    Repo.all(PageVersion)
  end

  def list_page_versions_for_page_id(id) do
    Repo.all(from(pv in PageVersion, where: pv.page_id == ^id))
  end

  @doc """
  Gets a single page_version.

  Raises `Ecto.NoResultsError` if the Page version does not exist.

  ## Examples

      iex> get_page_version!(123)
      %PageVersion{}

      iex> get_page_version!(456)
      ** (Ecto.NoResultsError)

  """
  def get_page_version!(id), do: Repo.get!(PageVersion, id)

  @doc """
  Creates a page_version.

  ## Examples

      iex> create_page_version(%{field: value})
      {:ok, %PageVersion{}}

      iex> create_page_version(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_page_version(attrs) do
    attrs
    |> PageVersion.changeset()
    |> Repo.insert()
  end

  def create_version_for_page(%Page{id: id, version: version, template: template}) do
    %{version: version, page_id: id, template: template}
    |> PageVersion.changeset()
    |> Repo.insert()
  end

  @doc """
  Updates a page_version.

  ## Examples

      iex> update_page_version(page_version, %{field: new_value})
      {:ok, %PageVersion{}}

      iex> update_page_version(page_version, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_page_version(%PageVersion{} = page_version, attrs) do
    page_version
    |> PageVersion.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a page_version.

  ## Examples

      iex> delete_page_version(page_version)
      {:ok, %PageVersion{}}

      iex> delete_page_version(page_version)
      {:error, %Ecto.Changeset{}}

  """
  def delete_page_version(%PageVersion{} = page_version) do
    Repo.delete(page_version)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking page_version changes.

  ## Examples

      iex> change_page_version(page_version)
      %Ecto.Changeset{data: %PageVersion{}}

  """
  def change_page_version(%PageVersion{} = page_version, attrs \\ %{}) do
    PageVersion.changeset(page_version, attrs)
  end

  @doc """
  Returns the list of beacon_page_events.

  ## Examples

      iex> list_beacon_page_events()
      [%PageEvent{}, ...]

  """
  def list_beacon_page_events do
    Repo.all(PageEvent)
  end

  @doc """
  Gets a single page_event.

  Raises `Ecto.NoResultsError` if the Page event does not exist.

  ## Examples

      iex> get_page_event!(123)
      %PageEvent{}

      iex> get_page_event!(456)
      ** (Ecto.NoResultsError)

  """
  def get_page_event!(id), do: Repo.get!(PageEvent, id)

  @doc """
  Creates a page_event.

  ## Examples

      iex> create_page_event(%{field: value})
      {:ok, %PageEvent{}}

      iex> create_page_event(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_page_event(attrs \\ %{}) do
    attrs
    |> PageEvent.changeset()
    |> Repo.insert()
    |> case do
      {:ok, page_event} ->
        unless Map.get(attrs, :skip_reload, false) do
          DBLoader.load_from_db()
        end

        {:ok, page_event}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Same as create_page_event/1 but raises when there are validation errors.
  """
  def create_page_event!(attrs \\ %{}) do
    case create_page_event(attrs) do
      {:ok, page_event} -> page_event
      {:error, changeset} -> raise "Failed to create page_event #{inspect(changeset.errors)} "
    end
  end

  @doc """
  Creates a page_helper.

  ## Examples

      iex> create_page_helper(%{field: value})
      {:ok, %PageHelper{}}

      iex> create_page_helper(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_page_helper(attrs) do
    attrs
    |> PageHelper.changeset()
    |> Repo.insert()
    |> case do
      {:ok, page_helper} ->
        unless Map.get(attrs, :skip_reload, false) do
          DBLoader.load_from_db()
        end

        {:ok, page_helper}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Same as create_page_helper/1 but raises when there are validation errors.
  """
  def create_page_helper!(attrs) do
    case create_page_helper(attrs) do
      {:ok, page_helper} -> page_helper
      {:error, changeset} -> raise "Failed to create page_helper #{inspect(changeset.errors)} "
    end
  end

  @doc """
  Updates a page_event.

  ## Examples

      iex> update_page_event(page_event, %{field: new_value})
      {:ok, %PageEvent{}}

      iex> update_page_event(page_event, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_page_event(%PageEvent{} = page_event, attrs) do
    page_event
    |> PageEvent.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a page_event.

  ## Examples

      iex> delete_page_event(page_event)
      {:ok, %PageEvent{}}

      iex> delete_page_event(page_event)
      {:error, %Ecto.Changeset{}}

  """
  def delete_page_event(%PageEvent{} = page_event) do
    Repo.delete(page_event)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking page_event changes.

  ## Examples

      iex> change_page_event(page_event)
      %Ecto.Changeset{data: %PageEvent{}}

  """
  def change_page_event(%PageEvent{} = page_event, attrs \\ %{}) do
    PageEvent.changeset(page_event, attrs)
  end
end
