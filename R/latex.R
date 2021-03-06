#' Convert R Markdown to a PDF book
#'
#' Convert R Markdown files to PDF while resolving the special tokens of
#' \pkg{bookdown} (e.g., the tokens for references and labels) to native LaTeX
#' commands.
#'
#' This function is based on \code{rmarkdown::\link{pdf_document}} (by default)
#' with better default arguments. You can also change the default format to
#' other LaTeX/PDF format functions using the \code{base_format} argument.
#' @param toc,number_sections,fig_caption See
#'   \code{rmarkdown::\link{pdf_document}}, or the documentation of the
#'   \code{base_format} function.
#' @param ... Other arguments to be passed to \code{base_format}.
#' @param base_format An output format function to be used as the base format.
#' @param toc_unnumbered Whether to add unnumberred headers to the table of
#'   contents.
#' @param toc_appendix Whether to add the appendix to the table of contents.
#' @param toc_bib Whether to add the bibliography section to the table of
#'   contents.
#' @param quote_footer If a character vector of length 2 and the quote footer
#'   starts with three dashes (\samp{---}), \code{quote_footer[1]} will be
#'   prepended to the footer, and \code{quote_footer[2]} will be appended; if
#'   \code{NULL}, the quote footer will not be processed.
#' @export
pdf_book = function(
  toc = TRUE, number_sections = TRUE, fig_caption = TRUE, ...,
  base_format = rmarkdown::pdf_document, toc_unnumbered = TRUE,
  toc_appendix = FALSE, toc_bib = FALSE, quote_footer = NULL
) {
  base_format = get_base_format(base_format)
  config = base_format(
    toc = toc, number_sections = number_sections, fig_caption = fig_caption, ...
  )
  config$pandoc$ext = '.tex'
  post = config$post_processor  # in case a post processor have been defined
  config$post_processor = function(metadata, input, output, clean, verbose) {
    if (is.function(post)) output = post(metadata, input, output, clean, verbose)
    f = with_ext(output, '.tex')
    x = resolve_refs_latex(readUTF8(f))
    x = restore_part_latex(x)
    x = restore_appendix_latex(x, toc_appendix)
    if (!toc_unnumbered) x = remove_toc_items(x)
    if (toc_bib) x = add_toc_bib(x)
    x = restore_block2(x)
    if (!is.null(quote_footer)) {
      if (length(quote_footer) != 2 || !is.character(quote_footer)) warning(
        "The 'quote_footer' argument should be a character vector of length 2"
      ) else x = process_quote_latex(x, quote_footer)
    }
    writeUTF8(x, f)
    latexmk(f, config$pandoc$latex_engine)
    unlink(with_ext(output, 'bbl'))  # not sure why latexmk left a .bbl there

    output = with_ext(output, '.pdf')
    o = opts$get('output_dir')
    keep_tex = isTRUE(config$pandoc$keep_tex)
    if (!keep_tex) file.remove(f)
    if (is.null(o)) return(output)

    output2 = file.path(o, output)
    file.rename(output, output2)
    if (keep_tex) file.rename(f, file.path(o, f))
    output2
  }
  # always enable tables (use packages booktabs, longtable, ...)
  pre = config$pre_processor
  config$pre_processor = function(...) {
    c(if (is.function(pre)) pre(...), '--variable', 'tables=yes', '--standalone')
  }
  config$bookdown_output_format = 'latex'
  config = set_opts_knit(config)
  config
}

#' @rdname html_document2
#' @export
pdf_document2 = function(...) {
  pdf_book(..., base_format = rmarkdown::pdf_document)
}

#' @rdname html_document2
#' @export
tufte_handout2 = function(...) {
  pdf_book(..., base_format = tufte::tufte_handout)
}

#' @rdname html_document2
#' @export
tufte_book2 = function(...) {
  pdf_book(..., base_format = tufte::tufte_book)
}

resolve_refs_latex = function(x) {
  # equation references \eqref{}
  x = gsub(
    '(?<!\\\\textbackslash{})@ref\\((eq:[-/:[:alnum:]]+)\\)', '\\\\eqref{\\1}', x,
    perl = TRUE
  )
  # normal references \ref{}
  x = gsub(
    '(?<!\\\\textbackslash{})@ref\\(([-/:[:alnum:]]+)\\)', '\\\\ref{\\1}', x,
    perl = TRUE
  )
  x = gsub(sprintf('\\(\\\\#((%s):[-/[:alnum:]]+)\\)', reg_label_types), '\\\\label{\\1}', x)
  x
}

restore_part_latex = function(x) {
  r = '^\\\\chapter\\*\\{\\(PART\\) '
  i = grep(r, x)
  if (length(i) == 0) return(x)
  x[i] = gsub(r, '\\\\part{', x[i])
  # remove the line \addcontentsline since it is not really a chapter title
  j = grep('\\addcontentsline{toc}{chapter}{(PART) ', x[i + 1], fixed = TRUE)
  x[(i + 1)[j]] = ''
  x
}

restore_appendix_latex = function(x, toc = FALSE) {
  r = '^\\\\chapter\\*\\{\\(APPENDIX\\) '
  i = find_appendix_line(r, x)
  if (length(i) == 0) return(x)
  x[i] = '\\appendix'
  if (toc) x[i] = paste(x[i], '\\addcontentsline{toc}{chapter}{\\appendixname}')
  if (grepl('^\\\\addcontentsline', x[i + 1])) x[i + 1] = ''
  x
}

find_appendix_line = function(r, x) {
  i = grep(r, x)
  if (length(i) > 1) stop('You must not have more than one appendix title')
  i
}

remove_toc_items = function(x) {
  r = '^\\\\addcontentsline\\{toc\\}\\{(part|chapter|section|subsection|subsubsection)\\}\\{.+\\}$'
  x[grep(r, x)] = ''
  x
}

add_toc_bib = function(x) {
  r = '^\\\\bibliography\\{.+\\}$'
  i = grep(r, x)
  if (length(i) == 0) return(x)
  i = i[1]
  x[i] = paste0(x[i], '\n\\addcontentsline{toc}{chapter}{\\bibname}')
  x
}

restore_block2 = function(x) {
  i = grep('^\\\\begin\\{document\\}', x)[1]
  if (is.na(i)) return(x)
  if (length(grep('\\\\(Begin|End)KnitrBlock', tail(x, -i))))
    x = append(x, '\\let\\BeginKnitrBlock\\begin \\let\\EndKnitrBlock\\end', i - 1)
  r = '^(.*\\\\BeginKnitrBlock\\{[^}]+\\})(\\\\iffalse\\{-)([-0-9]+)(-\\}\\\\fi)(.*)$'
  if (length(i <- grep(r, x)) == 0) return(x)
  opts = sapply(strsplit(gsub(r, '\\3', x[i]), '-'), function(z) {
    intToUtf8(as.integer(z))
  }, USE.NAMES = FALSE)
  x[i] = paste0(gsub(r, '\\1', x[i]), opts, gsub(r, '\\5', x[i]))
  x
}

process_quote_latex = function(x, commands) {
  for (i in grep('^\\\\end\\{quote\\}$', x)) {
    if (!grepl('^---.+', x[i - 1])) next
    x[i - 1] = paste0(commands[1], x[i - 1], commands[2])
  }
  x
}

latexmk = function(...) {
  FUN = getFromNamespace('latexmk', 'rmarkdown')
  FUN(...)
}
