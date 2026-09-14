require "test_helper"

class Reader::ClippingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    set_reader_credentials!
    @html = file_fixture("article.html").read
    @original_transport = HttpTransport.default
    HttpTransport.default = transport_always(http_response(200, @html))
  end

  teardown do
    HttpTransport.default = @original_transport
    restore_reader_credentials!
  end

  test "shows only the clippings waiting for the next issue" do
    get reader_clippings_path, headers: reader_headers

    assert_response :success
    assert_select "body", /Rails 8\.1 ships with a new queue UI/
    assert_select "body", /Understanding Solid Queue internals/
    assert_select "body", text: /Show HN/, count: 0 # already sent last week
    assert_select "body", /2 recortes vão na próxima edição semanal/
  end

  test "shows the summary and its status" do
    get reader_clippings_path, headers: reader_headers

    assert_response :success
    assert_select "body", /O Rails 8\.1 traz um novo painel de filas\./
    assert_select "body", /resumo pronto/
    assert_select "body", /resumo pendente/
  end

  test "shows the source feed of each clipping" do
    get reader_clippings_path, headers: reader_headers

    assert_response :success
    assert_select "body", /Ruby Weekly/
  end

  test "shows both languages of a clipping" do
    get reader_clippings_path, headers: reader_headers

    assert_response :success
    # The original (en-US) and its pt-BR translation, each labelled.
    assert_select "body", /Rails 8\.1 ships with a new queue UI/
    assert_select "body", /O Rails 8\.1 traz uma nova interface de filas/
    assert_select "body", /original/
    assert_select "body", /tradução/
  end

  test "shows the detected language of a summarized clipping" do
    get reader_clippings_path, headers: reader_headers

    assert_response :success
    assert_select "body", /en-US/
    # The one still waiting has no language yet.
    assert_select "body", /idioma não detectado/
  end

  test "flags a translation that is still pending" do
    clipping = clippings(:pending)
    clipping.update_columns(language: "en-US", title_translated: nil, summary_translated: nil,
                            summary_status: "summarized")

    get reader_clippings_path, headers: reader_headers

    assert_response :success
    assert_select "body", /tradução pendente/
  end

  test "removing a clipping takes it out of the queue" do
    clipping = clippings(:queued)

    assert_difference -> { Clipping.count }, -1 do
      delete reader_clipping_path(clipping), headers: reader_headers
    end

    assert_redirected_to reader_clippings_path

    get reader_clippings_path, headers: reader_headers
    assert_select ".flash--notice", /Removido da fila/
  end

  test "removing a clipping lets the same entry be clipped again" do
    clipping = clippings(:queued)
    delete reader_clipping_path(clipping), headers: reader_headers

    assert_difference -> { Clipping.count }, 1 do
      post clip_reader_entry_path(clipping.entry), headers: reader_headers
    end
  end

  test "generating the summary requeues it" do
    clipping = clippings(:pending)
    clipping.update!(summary_status: :failed, summary_error: "boom")

    assert_enqueued_with(job: GenerateSummaryJob, args: [ clipping.id ]) do
      post generate_summary_reader_clipping_path(clipping), headers: reader_headers
    end

    clipping.reload
    assert clipping.pending?
    assert_nil clipping.summary_error
    assert_redirected_to reader_clippings_path
  end

  test "an empty queue says so" do
    Clipping.unsent.destroy_all

    get reader_clippings_path, headers: reader_headers

    assert_response :success
    assert_select "body", /Nenhum recorte na fila/
  end

  test "links to the sent issues" do
    get reader_clippings_path, headers: reader_headers

    assert_select "a[href=?]", reader_newsletters_path
  end

  test "adds a clipping by URL, fetching its title and text" do
    assert_difference -> { Clipping.count }, 1 do
      assert_enqueued_with(job: GenerateSummaryJob) do
        post reader_clippings_path,
             params: { clipping: { url: "https://example.com/post" } },
             headers: reader_headers
      end
    end

    clipping = Clipping.order(:id).last
    assert clipping.manual?
    assert_nil clipping.entry_id
    assert_equal "Rails ships a new queue UI", clipping.title
    assert_equal "example.com", clipping.source_name
    assert_includes clipping.source_text, "Solid Queue replaces Redis"
    assert clipping.pending?
    assert_redirected_to reader_clippings_path
  end

  test "a YouTube URL takes the channel name as the source" do
    oembed = JSON.generate("author_name" => "Canal Exemplo")
    HttpTransport.default = transport_returning(http_response(200, oembed), http_response(200, @html))

    post reader_clippings_path,
         params: { clipping: { url: "https://www.youtube.com/watch?v=abc123" } },
         headers: reader_headers

    clipping = Clipping.order(:id).last
    assert_equal "Canal Exemplo", clipping.source_name

    get reader_clippings_path, headers: reader_headers
    assert_select "body", /Canal Exemplo/
  end

  test "a title typed by hand wins over the fetched one" do
    post reader_clippings_path,
         params: { clipping: { url: "https://example.com/post", title: "Meu título" } },
         headers: reader_headers

    assert_equal "Meu título", Clipping.order(:id).last.title
  end

  test "still creates the clipping when the page cannot be fetched" do
    HttpTransport.default = transport_always(http_response(404, "gone"))

    assert_difference -> { Clipping.count }, 1 do
      assert_no_enqueued_jobs(only: GenerateSummaryJob) do
        post reader_clippings_path,
             params: { clipping: { url: "https://example.com/post" } },
             headers: reader_headers
      end
    end

    clipping = Clipping.order(:id).last
    assert clipping.failed?
    assert_match(/404/, clipping.summary_error)
    assert_equal "example.com", clipping.title
    # The source does not depend on the fetch, so it is stored anyway.
    assert_equal "example.com", clipping.source_name
    # Sent to the edit page so the text can be pasted in.
    assert_redirected_to edit_reader_clipping_path(clipping)
  end

  test "does not queue the same URL twice" do
    assert_no_difference -> { Clipping.count } do
      post reader_clippings_path,
           params: { clipping: { url: clippings(:queued).url } },
           headers: reader_headers
    end

    assert_redirected_to reader_clippings_path
    get reader_clippings_path, headers: reader_headers
    assert_select ".flash--alert", /já está na fila/
  end

  test "refuses something that is not a URL" do
    assert_no_difference -> { Clipping.count } do
      post reader_clippings_path,
           params: { clipping: { url: "not-a-url" } },
           headers: reader_headers
    end

    assert_redirected_to reader_clippings_path
  end

  test "shows the source of a manual clipping in the list" do
    post reader_clippings_path, params: { clipping: { url: "https://example.com/post" } }, headers: reader_headers

    get reader_clippings_path, headers: reader_headers

    assert_select "body", /example\.com/
  end

  test "a manual clipping without a source is still marked as manual" do
    Clipping.create!(title: "Sem fonte", url: "https://example.org/sem-fonte", summary_status: "summarized")

    get reader_clippings_path, headers: reader_headers

    assert_select "body", /manual/
  end

  test "shows a failed clipping and says it stays out of the issue" do
    clippings(:pending).update!(summary_status: :failed, summary_error: "sem fonte")

    get reader_clippings_path, headers: reader_headers

    assert_response :success
    assert_select "body", /resumo falhou/
    assert_select "body", /fica de fora/
    assert_select "body", /sem fonte/
  end

  test "the edit page shows the url and the content per language" do
    clipping = clippings(:queued) # written in en-US, with a pt-BR translation

    get edit_reader_clipping_path(clipping), headers: reader_headers

    assert_response :success
    assert_select "input[name=?][value=?]", "clipping[url]", clipping.url
    assert_select "input[name=?][value=?]", "clipping[title_en_us]", clipping.title
    assert_select "input[name=?][value=?]", "clipping[title_pt_br]", clipping.title_translated
    assert_select "textarea[name=?]", "clipping[summary_en_us]"
    assert_select "textarea[name=?]", "clipping[summary_pt_br]"
    assert_select "textarea[name=?]", "clipping[source_text]"
    assert_select "select[name=?] option[selected][value=?]", "clipping[language]", "en-US"
    assert_select "form button", /gerar sumário e tradução/
  end

  test "updating writes the per-language content to the right columns" do
    clipping = clippings(:queued)

    patch reader_clipping_path(clipping),
          params: { clipping: {
            url: clipping.url,
            language: "en-US",
            source_text: "novo texto",
            title_pt_br: "Título PT", summary_pt_br: "Resumo PT",
            title_en_us: "Title EN", summary_en_us: "Summary EN"
          } },
          headers: reader_headers

    clipping.reload
    assert_equal "Title EN", clipping.title
    assert_equal "Título PT", clipping.title_translated
    assert_equal "Summary EN", clipping.summary
    assert_equal "Resumo PT", clipping.summary_translated
    assert_equal "novo texto", clipping.source_text
    assert_redirected_to reader_clippings_path
  end

  test "changing the language re-maps which column holds the original" do
    clipping = clippings(:queued)

    patch reader_clipping_path(clipping),
          params: { clipping: {
            url: clipping.url, language: "pt-BR",
            title_pt_br: "Título PT", summary_pt_br: "Resumo PT",
            title_en_us: "Title EN", summary_en_us: "Summary EN"
          } },
          headers: reader_headers

    clipping.reload
    assert_equal "pt-BR", clipping.language
    assert_equal "Título PT", clipping.title
    assert_equal "Title EN", clipping.title_translated
    assert_equal "Resumo PT", clipping.summary
    assert_equal "Summary EN", clipping.summary_translated
    assert_equal "Title EN", clipping.title_for("en-US")
  end

  test "a manual clipping can be completed by hand and generated" do
    post reader_clippings_path,
         params: { clipping: { url: "https://example.com/post", title: "Título" } },
         headers: reader_headers
    clipping = Clipping.order(:id).last

    patch reader_clipping_path(clipping),
          params: { clipping: { url: clipping.url, source_text: "Texto colado à mão." } },
          headers: reader_headers

    assert_equal "Texto colado à mão.", clipping.reload.source_text

    assert_enqueued_with(job: GenerateSummaryJob, args: [ clipping.id ]) do
      post generate_summary_reader_clipping_path(clipping), headers: reader_headers
    end

    assert clipping.reload.pending?
  end
end
