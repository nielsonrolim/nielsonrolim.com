require "test_helper"

class Reader::ClippingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as_admin
    @html = file_fixture("article.html").read
    @original_transport = HttpTransport.default
    HttpTransport.default = transport_always(http_response(200, @html))
  end

  teardown do
    HttpTransport.default = @original_transport
    sign_out
  end

  test "shows only the clippings waiting for the next issue" do
    get reader_clippings_path

    assert_response :success
    assert_select "body", /Rails 8\.1 ships with a new queue UI/
    assert_select "body", /Understanding Solid Queue internals/
    assert_select "body", text: /Show HN/, count: 0 # already sent last week
    assert_select "body", /2 recortes vão na próxima edição semanal/
  end

  test "shows the summary and its status" do
    get reader_clippings_path

    assert_response :success
    assert_select "body", /O Rails 8\.1 traz um novo painel de filas\./
    assert_select "body", /resumo pronto/
    assert_select "body", /resumo pendente/
  end

  test "shows the source feed of each clipping" do
    get reader_clippings_path

    assert_response :success
    assert_select "body", /Ruby Weekly/
  end

  test "shows both languages of a clipping" do
    get reader_clippings_path

    assert_response :success
    # Both editions of the bilingual clipping.
    assert_select "body", /Rails 8\.1 ships with a new queue UI/
    assert_select "body", /O Rails 8\.1 traz uma nova interface de filas/
    assert_select "body", /publicado/
  end

  test "labels an edition without a URL as a translation" do
    clipping = Clipping.new(source_name: "example.com", summary_status: :summarized)
    clipping.variants.build(locale: "en-US", url: "https://example.com/a",
                            title: "English title", summary: "Summary.", origin: :generated)
    clipping.variants.build(locale: "pt-BR", title: "Título", summary: "Resumo.", origin: :generated)
    clipping.save!

    get reader_clippings_path

    assert_response :success
    assert_select "body", /publicado/
    assert_select "body", /tradução/
  end

  test "shows the languages a summarized clipping is published in" do
    get reader_clippings_path

    assert_response :success
    assert_select "body", /en-US/
    # The one still waiting has no language yet.
    assert_select "body", /idioma não detectado/
  end

  test "flags a translation that is still pending" do
    clipping = clippings(:queued)
    clipping.variant_for("pt-BR").destroy
    clipping.update_columns(summary_status: "summarized")

    get reader_clippings_path

    assert_response :success
    assert_select "body", /tradução pendente/
  end

  test "removing a clipping takes it out of the queue" do
    clipping = clippings(:queued)

    assert_difference -> { Clipping.count }, -1 do
      delete reader_clipping_path(clipping)
    end

    assert_redirected_to reader_clippings_path

    get reader_clippings_path
    assert_select ".toast--notice", /Removido da fila/
  end

  test "removing a clipping lets the same entry be clipped again" do
    clipping = clippings(:queued)
    delete reader_clipping_path(clipping)

    assert_difference -> { Clipping.count }, 1 do
      post clip_reader_entry_path(clipping.entry)
    end
  end

  test "generating the summary requeues it" do
    clipping = clippings(:pending)
    clipping.update!(summary_status: :failed, summary_error: "boom")

    assert_enqueued_with(job: GenerateSummaryJob, args: [ clipping.id ]) do
      post generate_summary_reader_clipping_path(clipping)
    end

    clipping.reload
    assert clipping.pending?
    assert_nil clipping.summary_error
    assert_redirected_to reader_clippings_path
  end

  test "an empty queue says so" do
    Clipping.unsent.destroy_all

    get reader_clippings_path

    assert_response :success
    assert_select "body", /Nenhum recorte na fila/
  end

  test "links to the sent issues" do
    get reader_clippings_path

    assert_select "a[href=?]", reader_newsletters_path
  end

  test "adds a clipping by URL, fetching its title and text" do
    assert_difference -> { Clipping.count }, 1 do
      assert_enqueued_with(job: GenerateSummaryJob) do
        post reader_clippings_path,
             params: { clipping: { url: "https://example.com/post" } }
      end
    end

    clipping = Clipping.order(:id).last
    assert clipping.manual?
    assert_nil clipping.entry_id
    assert_equal "Rails ships a new queue UI", clipping.display_title
    assert_equal "example.com", clipping.source_name
    assert_includes clipping.source_text, "Solid Queue replaces Redis"
    assert_nil clipping.primary_variant.locale
    assert clipping.pending?
    assert_redirected_to reader_clippings_path
  end

  test "a YouTube URL takes the channel name as the source" do
    oembed = JSON.generate("author_name" => "Canal Exemplo")
    HttpTransport.default = transport_returning(http_response(200, oembed), http_response(200, @html))

    post reader_clippings_path,
         params: { clipping: { url: "https://www.youtube.com/watch?v=abc123" } }

    clipping = Clipping.order(:id).last
    assert_equal "Canal Exemplo", clipping.source_name

    get reader_clippings_path
    assert_select "body", /Canal Exemplo/
  end

  test "a title typed by hand wins over the fetched one" do
    post reader_clippings_path,
         params: { clipping: { url: "https://example.com/post", title: "Meu título" } }

    assert_equal "Meu título", Clipping.order(:id).last.display_title
  end

  test "still creates the clipping when the page cannot be fetched" do
    HttpTransport.default = transport_always(http_response(404, "gone"))

    assert_difference -> { Clipping.count }, 1 do
      assert_no_enqueued_jobs(only: GenerateSummaryJob) do
        post reader_clippings_path,
             params: { clipping: { url: "https://example.com/post" } }
      end
    end

    clipping = Clipping.order(:id).last
    assert clipping.failed?
    assert_match(/404/, clipping.summary_error)
    assert_equal "example.com", clipping.display_title
    # The source does not depend on the fetch, so it is stored anyway.
    assert_equal "example.com", clipping.source_name
    # Sent to the edit page so the text can be pasted in.
    assert_redirected_to edit_reader_clipping_path(clipping)
  end

  test "does not queue the same URL twice" do
    existing = clippings(:queued).variant_for("en-US").url

    assert_no_difference -> { Clipping.count } do
      post reader_clippings_path,
           params: { clipping: { url: existing } }
    end

    assert_redirected_to reader_clippings_path
    get reader_clippings_path
    assert_select ".toast--alert", /já está na fila/
  end

  test "refuses something that is not a URL" do
    assert_no_difference -> { Clipping.count } do
      post reader_clippings_path,
           params: { clipping: { url: "not-a-url" } }
    end

    assert_redirected_to reader_clippings_path
  end

  test "shows the source of a manual clipping in the list" do
    post reader_clippings_path, params: { clipping: { url: "https://example.com/post" } }

    get reader_clippings_path

    assert_select "body", /example\.com/
  end

  test "a manual clipping without a source is still marked as manual" do
    clipping = Clipping.new(summary_status: "summarized")
    clipping.variants.build(url: "https://example.org/sem-fonte", title: "Sem fonte")
    clipping.save!

    get reader_clippings_path

    assert_select "body", /manual/
  end

  test "shows a failed clipping and says it stays out of the issue" do
    clippings(:pending).update!(summary_status: :failed, summary_error: "sem fonte")

    get reader_clippings_path

    assert_response :success
    assert_select "body", /resumo falhou/
    assert_select "body", /fica de fora/
    assert_select "body", /sem fonte/
  end

  test "the edit page shows the URL and content per language" do
    clipping = clippings(:queued) # written in en-US, with a pt-BR edition

    get edit_reader_clipping_path(clipping)

    assert_response :success
    assert_select "input[name=?][value=?]", "clipping[url_en_us]", clipping.variant_for("en-US").url
    assert_select "input[name=?][value=?]", "clipping[title_en_us]", clipping.variant_for("en-US").title
    assert_select "input[name=?][value=?]", "clipping[url_pt_br]", clipping.variant_for("pt-BR").url
    assert_select "input[name=?][value=?]", "clipping[title_pt_br]", clipping.variant_for("pt-BR").title
    assert_select "textarea[name=?]", "clipping[summary_en_us]"
    assert_select "textarea[name=?]", "clipping[summary_pt_br]"
    assert_select "textarea[name=?]", "clipping[source_text]"
    assert_select "form button", /gerar sumário e tradução/
  end

  test "updating writes each language to its own edition" do
    clipping = clippings(:queued)

    patch reader_clipping_path(clipping),
          params: { clipping: {
            source_text: "novo texto",
            url_en_us: "https://example.com/en", title_en_us: "Title EN", summary_en_us: "Summary EN",
            url_pt_br: "https://example.com/pt", title_pt_br: "Título PT", summary_pt_br: "Resumo PT"
          } }

    clipping.reload
    assert_equal "Title EN", clipping.title_for("en-US")
    assert_equal "Título PT", clipping.title_for("pt-BR")
    assert_equal "Summary EN", clipping.summary_for("en-US")
    assert_equal "Resumo PT", clipping.summary_for("pt-BR")
    assert_equal "https://example.com/en", clipping.url_for("en-US")
    assert_equal "https://example.com/pt", clipping.url_for("pt-BR")
    assert_equal "novo texto", clipping.source_text
    assert clipping.variant_for("pt-BR").manual?
    assert_redirected_to reader_clippings_path
  end

  test "updating can clear an edition's URL without filling it from the other" do
    clipping = clippings(:queued)

    patch reader_clipping_path(clipping),
          params: { clipping: {
            url_en_us: clipping.variant_for("en-US").url, title_en_us: "Title EN", summary_en_us: "Summary EN",
            url_pt_br: "", title_pt_br: "Título PT", summary_pt_br: "Resumo PT"
          } }

    clipping.reload
    assert_equal "https://example.com/rails-8-1", clipping.variant_for("en-US").url
    assert_nil clipping.variant_for("pt-BR").url
    # The blank edition still points readers at the one that exists.
    assert_equal "https://example.com/rails-8-1", clipping.url_for("pt-BR")
  end

  test "leaving a language blank drops its edition" do
    clipping = clippings(:queued)

    patch reader_clipping_path(clipping),
          params: { clipping: {
            url_en_us: clipping.variant_for("en-US").url, title_en_us: "Title EN", summary_en_us: "Summary EN",
            url_pt_br: "", title_pt_br: "", summary_pt_br: ""
          } }

    clipping.reload
    assert_equal "Title EN", clipping.title_for("en-US")
    assert_nil clipping.variant_for("pt-BR")
    assert_nil clipping.summary_for("pt-BR")
  end

  test "a manual clipping can be completed by hand and generated" do
    post reader_clippings_path,
         params: { clipping: { url: "https://example.com/post", title: "Título" } }
    clipping = Clipping.order(:id).last

    patch reader_clipping_path(clipping),
          params: { clipping: { source_text: "Texto colado à mão." } }

    assert_equal "Texto colado à mão.", clipping.reload.source_text

    assert_enqueued_with(job: GenerateSummaryJob, args: [ clipping.id ]) do
      post generate_summary_reader_clipping_path(clipping)
    end

    assert clipping.reload.pending?
  end
end
