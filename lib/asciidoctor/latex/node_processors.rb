require 'asciidoctor'
require 'asciidoctor/latex/core_ext/colored_string'
require 'asciidoctor/latex/core_ext/utility'
require 'htmlentities'

module TexUtilities
  def self.braces(*args)
    args.map{|arg| "《#{arg}》"}.join("")
  end

  def self.macro(name, *args)
    "\\#{name}#{braces *args}"
  end

  def self.macro_opt(name, opt, *args)
    "\\#{name}〈#{opt}〉#{braces *args}"
  end

  # tex.region('bf', 'foo bar') => {\bf foo bar}
  def self.region(name, *args)
    "《\\#{name} #{args.join(" ")}》"
  end

  def self.apply_macros(macro_list, arg)
    val = arg
    macro_list.reverse.each do |macro_name|
      val = self.macro(macro_name, val)
    end
    val
  end

  def self.begin(arg)
    macro('begin', arg)
  end

  def self.end(arg)
    macro('end', arg)
  end

  def self.env(env, *args)
    body = args.pop
    "#{self.begin(env)}#{braces *args}\n#{body}\n#{self.end(env)}\n"
  end

  def self.env_opt(env, opt, *args)
    body = args.pop
    "#{self.begin(env)}〈#{opt}〉#{braces *args}\n#{body}\n#{self.end(env)}\n"
  end

  # normalize the name because it is an id
  # and so frequently contains underscores
  def self.hypertarget(name, text)
    if text
     # text = text.rstrip.chomp
    end
    if name
      "\\hypertarget《#{name.tex_normalize}》《#{text}》"
    else
      "\\hypertarget《'NO-ID'》《#{text}》"
      # FIXME: why do we need this branch?
    end
  end

  def self.escape(str)
    coder  = HTMLEntities.new
    str = coder.decode str
    str = str.gsub("{",     "\\{")
    str = str.gsub("}",     "\\}")
    str = str.gsub("&",     "\\\\&")
    str = str.gsub("#",     "\\\\#")
    str = str.gsub("%",     "\\%")
    str = str.gsub("$",     "\\$")
    str = str.gsub("_",     "\\_")
    str = str.gsub("|",     "\\textbar{}")
    str = str.gsub("~",     "\\textasciitilde{}")
    str = str.gsub("^",     "\\textasciicircum{}")
  end

  def self.mathEscape(str)
    coder  = HTMLEntities.new
    result = coder.decode(str)
    result = result.gsub("{", '《')
    result = result.gsub("}", '》')
    result = result.gsub("[", '〈')
    result = result.gsub("]", '〉')
  end
end

module Process
  include Asciidoctor::Latex
  include TexUtilities
  $tex = TexUtilities

  # ---------------------------------------------------------------------------
  # Public block processing methods

  def self.document(node)
    doc = ''

    unless node.embedded? or node.document.attributes['header'] == 'no'
      doc << "% ======================================================================\n"
      doc << "% Generated by asciidoctor-latex\n"

      filePreamble = File.join(Asciidoctor::Latex::DATA_DIR, "preamble_#{node.document.doctype}.tex")
      doc << self.insertFile( filePreamble )
      doc << "\n"

      doc << "% ======================================================================\n"
      doc << "% Macros and environments for asciidoc constructs\n"

      fileCommands = File.join(Asciidoctor::Latex::DATA_DIR, 'asciidoc_tex_macros.tex')
      doc << self.insertFile( fileCommands )
      doc << "\n"

      doc << "% ======================================================================\n"
      doc << "% Front matter\n"

      doc << $tex.macro( "title",  node.doctitle) + "\n"
      doc << $tex.macro( "author", node.author)   + "\n"
      doc << $tex.macro( "date",   node.revdate)  + "\n"

      doc << "\n\n\n"
      doc << $tex.begin( "document") + "\n"

      doc << self.insertTitle(node)
      doc << self.insertTableOfContents(node)
    end

    doc << node.content
    doc << "\n"

    unless node.embedded? or node.document.attributes['header'] == 'no'
      doc << $tex.end("document") + "\n"
    end

    return doc
  end

  def self.section(node)
    # The section levels are different in book and article
    tags = {
      'article' => [ 'part', 'section', 'subsection', 'subsubsection', 'paragraph' ],
      'book'    => [ 'part', 'chapter', 'section', 'subsection', 'subsubsection', 'paragraph' ]
    }

    # Choose the section's level
    section = tags[node.document.doctype][node.level]

    # Fallback when the requested heading level does not exist
    if section == nil
      section = tags[node.document.doctype][-1];
      warn "Latex #{node.document.doctype} does not support " +
           "heading level #{node.level}, uses #{section} instead".magenta
    end

    # Add a star at the end when not numbered
    section << (node.numbered ? '' : '*')

    # Generate the section's begin, content and end
    result  = $tex.macro(section, $tex.escape(node.title)) + "\n"
    result << node.content
    #result << "% end #{section}\n"

    return result
  end

  def self.paragraph(node)
    # Paragraph title
    title   = ""
    if node.title?
      title = $tex.macro("blockTitle", $tex.escape(node.title)) + "\n"
    end

    # Paragraph content with colorization
    color   = getColor(node.role)
    content = $tex.escape(node.content)
    if color != ""
      content = $tex.macro($colors[color], content)
    end

    # Text alignment (left, right, center, justify)
    alignement = getAlignment(node.role)
    if alignement != ""
      content = $tex.env($alignments[alignement], content)
    end

    return "#{title}#{content}\n\n"
  end

  def self.listing(node)
    # TODO: linenos, linenumbers
    # TODO: only include the needed converter
    # TODO: translate language names between converters
    result = ""
    language = node.attributes['language']

    case node.document.attributes['source-highlighter']
      when "pygment"
        result << $tex.env("minted", language, node.content)
  
      when "lstlisting"
        options = "frame = single, language=#{language}"
        result << $tex.env_opt("lstlisting", options, node.content)

      else
        result << $tex.env("verbatim", node.content)
    end

    return result
  end



  # ---------------------------------------------------------------------------
  # Public inline processing methods

  def self.inlineQuoted(node)
    result = ""

    case node.type
      when :monospaced
        if node.text.include? Asciidoctor::Substitutors::PASS_START
          # This is a passthrough text, use verbatim in latex
          # TODO: The braces are still escaped how to unescape them
          # TODO: Analyze the passtrough text to find an appropriate delimiter for the verb command
          #       where can I get a copy of the referenced text?
          result = "\\verb€#{node.text}€"
        else
          # This is a simple monotype text
          result = $tex.macro("texttt", node.text)
        end

      when :emphasis
        result = $tex.macro("textit", node.text)

      when :strong
        result = $tex.macro("textbf", node.text)

      when :double
        result = "``#{node.text}''"

      when :single
        result = "`#{node.text}'"

      when :mark
        result = $tex.macro("colorbox", "yellow", node.text)

      when :superscript
        result = $tex.macro("textsuperscript", node.text)

      when :subscript
        result = $tex.macro("textsubscript", node.text)

      when :asciimath
        warn "#{node.type} not suported in LaTeX backend".red
        result = "\\verb€#{node.text}€"

      when :latexmath
        # TODO: Is it possible to add the node.text to the passthrough 
        result = $tex.mathEscape(node.text)
        result = "\\( #{result} \\)"

      when :unquoted
        # TODO: look in the original asciidoctor for inline roles
        # TODO: Generate macros for each unknown role in the document
        color  = getColor(node.role)
        result = node.text
        result = $tex.macro($colors[color], result) if color != ""

        # In Asciidoctor, :literal type seems to be used only in block node
      #when :literal
      #  result = $tex.macro("texttt", node.text)

      # In Asciidoctor, :verse type seems to be used only in block node
      #when :verse
      #  result = $tex.macro("texttt", node.text)

    else
        warn "Unknown node type #{node.type}".magenta
        result = node.text
    end

    return result
  end









  # ---------------------------------------------------------------------------
  # Private variables and methods
  private

  $colors = {
    'red'    => "colorRed",
    'blue'   => "colorBlue",
    'green'  => "colorGreen",
    'yellow' => "colorYellow"
  }

  $alignments = {
    "text-left"   => "flushright",
    "text-right"  => "flushright",
    "text-center" => "center"
  }

  def self.getColor(role)
    result = ""
    if role != nil
      role.split.each { |item| result = item if $colors.include?(item) }
    end
    return result
  end

  def self.getAlignment(role)
    result = ""
    if role != nil
      role.split.each { |item| result = item if $alignments.include?(item) }
    end
    return result
  end

  def self.insertTitle(node)
    result = ""
    result << $tex.macro("maketitle") if node.attributes['notitle'] == nil
    return "#{result}\n"
  end

  def self.insertTableOfContents(node)
    result = ""
    result << $tex.macro("tableofcontents") if node.attributes['toc'] != nil
    return "#{result}\n"
  end

  def self.insertFile(fileName)
    result = ""
    result << File.open(fileName, 'r') { |f| f.read }
  end

end # module Process









# Yuuk!, The classes in node_processor implement the
# latex backend for Asciidoctor-latex.  This
# module is far from complete.
module Asciidoctor

  include TexUtilities
  $tex = TexUtilities




  # Write TeX \itemize or \enumerate lists
  # for ulist and olist.  Recurses for
  # nested lists.
  class List

    def tex_process
      case self.node_name
      when 'dlist'
        dlist_process
      when 'ulist'
        ulist_process
      when 'olist'
        olist_process
      else
        # warn "This Asciidoctor::List, tex_process.  I don't know how to do that (#{self.node_name})" if $VERBOSE
      end
    end

    def item(term, dd)
      if term != ""
        result = $tex.macro_opt("item", term) + "\n"
      else
        result = $tex.macro("item") + "\n"
      end

      # Generate the item and its content
      if dd
        result << $tex.escape(dd.text)    if dd.text?
        result << $tex.escape(dd.content) if dd.blocks?
        result << "\n"
      end
      return result
    end

    def dlist_process
      result = $tex.begin("description") + "\n"
      self.items.each do |terms, item|
        # terms.map{}.join generate a string from all terms text
        result << self.item(terms.map { |one| one.text }.join(""), item)
      end
      result << $tex.end("description")
    end

    def ulist_process
      result = $tex.begin("itemize") + "\n"
      self.content.each do |item|
        result << self.item("", item)
      end
      result << $tex.end("itemize")
    end

    def olist_process
      result = $tex.begin("enumerate") + "\n"
      self.content.each do |item|
        result << self.item("", item)
      end
      result << $tex.end("enumerate")
    end

  end

  # Proces block elements of varios kinds
  class Block

    # STANDARD_ENVIRONMENT_NAMES = %w(theorem proposition lemma definition example problem equation)
    STANDARD_ENVIRONMENT_NAMES = %w(equation)

    def tex_process
      case self.blockname
      #when :paragraph
      #  paragraph_process
      when :stem
        stem_process
      when :admonition
        admonition_process
      when :page_break
        page_break_process
      when :literal
        self.literal_process
      when :pass
        self.pass_process
      when :quote
        self.quote_process
      when :open
        self.open_process
      #when :listing
      #  self.listing_process
      when :example
        self.example_process
      when :floating_title
        self.floating_title_process
      when :image
        self.image_process
      when :preamble
        self.preamble_process
      when :sidebar
        self.sidebar_process
      when :verse
        self.verse_process
      when :toc
        self.toc_process
      # when :table
        # self.table_process
      else
        # warn "This is Asciidoctor::Block, tex_process.  I don't know how to do that (#{self.blockname})" if $VERBOSE if $VERBOSE
        ""
      end
    end

    def stem_process
      # Seems to work
      return "\\[#{self.content}\\]"
      #environment = Latex::TeXBlock.environment_type self.content
      #if Latex::TeXBlock::INNER_TYPES.include? environment
      #  "\\\[\n#{Latex::TeXPostProcess.stem_substitutions self.content}\n\\\]\n"
      #else
      #  self.content
      #end
    end

    def admonition_process
      content = self.content
      # Sometimes the admonition block is already escaped this one avoid doing it twice
      content = $tex.escape(content) if self.lines.length == 1
      result  = $tex.macro("begin", "admonition", self.style) + "\n"
      result << content + "\n"
      result << $tex.macro("end", "admonition") + "\n"
    end

    def page_break_process
      "\n\\vfill\\eject\n"
    end

    def literal_process
      heading = ''
      if id and self.title
        heading = $tex.hypertarget id, self.title
      elsif self.title
        heading = self.title
      end
      if heading == ''
        $tex.env 'verbatim', self.content
      else
        output = $tex.region 'bf', heading
        output << "\\vspace《-1\\baselineskip》\n"
        output << ($tex.env 'verbatim', self.content)
      end
    end

    def pass_process
      self.content
    end

    def quote_process
      if self.attr? 'attribution'
        attribution = self.attr 'attribution'
        citetitle = (self.attr? 'citetitle') ? (self.attr 'citetitle') : nil
        # citetitle = citetitle ? ' - ' + citetitle : ''
        citetitle = citetitle ? $tex.region('bf', citetitle) + ' \\\\' : ''
        $tex.env 'aquote', attribution, citetitle, self.content
      elsif self.title
        $tex.env 'tquote', self.title, self.content
      else
        $tex.env 'quotation', self.content
      end
    end



    ####################################################################

    def label
      if self.id
        label = $tex.macro 'label', self.id
        # label = $tex.macro 'label', $tex.hypertarget(self.id, self.id)
      else
        label = ""
      end
      label
    end

    def options
      self.attributes['options']
    end

    def env_title
      if self.attributes['original_title']
        "《\\rm (#{self.attributes['original_title']}) 》"
      else
        ''
      end
    end

    ####################################################################

    def label_line
      if label == ""
        ""
      else
        label + "\n"
      end
    end

    def handle_listing
      content = $tex.env 'verbatim', self.content
      $tex.env env, label, content
    end

    def handle_eqalign
      content = $tex.env 'aligned', "#{label_line}#{self.content.strip}"
      if options.include? 'numbered'
        $tex.env 'align', content
      else
        $tex.env 'align*', content
      end
    end

    def handle_equation
      if options.include? 'numbered'
        content = $tex.hypertarget self.id, self.content.strip
        $tex.env 'equation', "#{label_line}#{content}"
      else
        $tex.env 'equation*', "#{label_line}#{self.content.strip}"
      end
    end

    def handle_plain(env)

      if self.id and self.title
        _title = $tex.hypertarget self.id, self.env_title
      else
        _title = self.env_title
      end

      if self.attributes['plain-option']
        content = $tex.region 'rm', self.content.rstrip
      else
        content = self.content.rstrip
      end

      $tex.env env, "#{_title}#{label_line}#{content}\n"
    end

    ####################################################################

    def toc_process
      if document.attributes['toc-placement'] == 'macro'
        $tex.macro 'tableofcontents'
      end
      # warn "Please implement me! (toc_process)".red if $VERBOSE
    end

    def report
      # Report on this node
      warn ["OPEN BLOCK:".magenta, "id: #{self.id}"].join(" ")
      warn ["Node:".magenta, "#{self.blockname}".cyan].join(" ")
      warn ["Attributes:".magenta, "#{self.attributes}".cyan].join(" ")
      warn ["Title: ".magenta, title.cyan, "style:", self.style].join(" ") if title
      warn ["Content:".magenta, "#{self.content}".yellow].join(" ")
      warn ["Style:".green, "#{self.style}".red].join(" ")
      # warn ["METHODS:".red, "#{self.methods}".yellow].join(" ")
    end


    # Process open blocks.  Map a block of the form
    #
    # .Foo
    # [[hocus_pocus]]
    # --
    # La di dah
    # --
    #
    # to
    #
    # \begin{Foo}
    # \label{hocus_pocus}
    # La di dah
    # \end{Foo}
    #
    # This scheme enables one to map Asciidoc blocks to
    # LaTeX environments with essentally no knoweldge
    # of either other than their form.
    #
    def open_process

      attr = self.attributes

      # Get title !- nil or make a dummy one
      title = self.title? ? self.title : 'Dummy'

      # strip constructs like {counter:theorem} from the title
      title = title.gsub /\{.*?\}/, ""
      title = title.strip

      if attr['role'] == 'text-center'
        $tex.env 'center', self.content
      else
        self.content
      end

    end

    def example_process
      id = self.attributes['id']
      if self.title
        heading = $tex.region 'bf', self.title
        content  = "-- #{heading}.\n#{self.content}"
      else
        content = self.content
      end
      if id
        hypertarget = $tex.hypertarget id, self.content.split("\n")[0]
        content = "#{hypertarget}\n#{content}" if id
      end
      $tex.env 'example', content
    end


    def floating_title_process
      doctype = self.document.doctype

      tags = { 'article' => [ 'part',  'section', 'subsection', 'subsubsection', 'paragraph' ],
               'book' => [ 'part', 'chapter', 'section', 'subsection', 'subsubsection', 'paragraph' ] }

      tagname = tags[doctype][self.level]

      "\\#{tagname}*《#{self.title}》\n\n#{self.content}\n\n"
    end

    def image_process
      if self.attributes['width']
        width = self.attributes['width']
        if    width.include?("mm")
          width = "#{width.to_f}mm"
        elsif width.include?("cm")
          width = "#{width.to_f}cm"
        elsif width.include?("in")
          width = "#{width.to_f}in"
        elsif width.include?("%")
          width = "#{width.to_f/100}\\textwidth"
        else
          width = '\textwidth'
        end
      else
        width = '\textwidth'
      end
      raw_image = self.attributes['target']
      unless (imagesdir = document.attr 'imagesdir').nil_or_empty?
        raw_image = ::File.join imagesdir, raw_image
      end
      if document.attributes['noteshare'] == 'yes'
        image_rx = /image.*original\/(.*)\?/
        match_data = raw_image.match image_rx
        if match_data
          image = match_data[1]
        else
          image = "undefined"
        end
      else
        image = raw_image
      end
      if self.title?
        caption = "\\caption《#{self.title}》"
      else
        caption = ''
      end
      refs = self.parent.document.references  # [:ids]
      if self.attributes['align'] == 'center'
        align = '\\centering'
      else
        align = ''
      end
      float = self.attributes['float']
      if float
        figure_type = 'wrapfigure'
        ftext_width = width # '0.45\\textwidth'
        caption=''
      else
        figure_type = 'figure'
        ftext_width = ''
      end
      case float
      when 'left'
        position = '{l}'
      when 'right'
        position = '{r}'
      else
        position = '[h]'
      end
      # pos_option = "#{figure_type}}#{position}"
      # incl_graphics = $tex.macro_opt, "width=#{width}", image
      # $tex.env figure_type, "#{pos_option}\{#{ftext_width}\}", incl_graphics,
      #\n\\includegraphics[width=#{width}]{#{image}}\n#{caption}\n#{align}"
      "\\begin{#{figure_type}}#{position}《#{ftext_width}》\n\\centering\\includegraphics〈width=#{width}〉{#{image}}\n#{caption}\n#{align}\n\\end{#{figure_type}}\n"
    end





    def old_image_process
      if self.attributes['width']
        width = "#{self.attributes['width'].to_f/100.0}truein"
      else
        width = '2.5truein'
      end
      raw_image = self.attributes['target']
      unless (imagesdir = document.attr 'imagesdir').nil_or_empty?
        raw_image = ::File.join imagesdir, raw_image
      end
      if document.attributes['noteshare'] == 'yes'
        image_rx = /image.*original\/(.*)\?/
        match_data = raw_image.match image_rx
        if match_data
          image = match_data[1]
        else
          image = "undefined"
        end
      else
        image = raw_image
      end
      if self.title?
        caption = "\\caption《#{self.title}》"
      else
        caption = ''
      end
      refs = self.parent.document.references  # [:ids]
      if self.attributes['align'] == 'center'
        align = '\\centering'
      else
        align = ''
      end
      float = self.attributes['float']
      if float
        figure_type = 'wrapfigure'
        ftext_width = width # '0.45\\textwidth'
        caption=''
      else
        figure_type = 'figure'
        text_width = ''
      end
      case float
      when 'left'
        position = '《l》'
      when 'right'
        position = '《r》'
      else
        position = '〈h〉'
      end
      # pos_option = "#{figure_type}}#{position}"
      # incl_graphics = $tex.macro_opt, "width=#{width}", image
      # $tex.env figure_type, "#{pos_option}《#{ftext_width}》", incl_graphics,
      #\n\\includegraphics〈width=#{width}]{#{image}}\n#{caption}\n#{align}"
      "\\begin{#{figure_type}}#{position}《#{ftext_width}》\n\\centering\\includegraphics〈width=#{width}〉{#{image}}\n#{caption}\n#{align}\n\\end{#{figure_type}}\n"
    end

    def preamble_process
      # "\\begin《preamble》\n%% HO HO HO!\n#{self.content}\n\\end《preamble》\n"
      self.content
    end


    def sidebar_process
      title = self.title
      attr = self.attributes
      id = attr['id']
      if id
        content = "\\hypertarget《#{id}》《#{self.content.rstrip}》"
      else
        content = self.content
      end
      if title
        title  = $tex.env 'bf', title
        $tex.env 'sidebar', "#{title}\n#{content.rstrip}"
      else
        $tex.env 'sidebar', content
      end
    end

    def verse_process
      # $tex.env 'alltt', self.content
      $tex.env 'verse', self.content
    end

  end # class Block

  # Process inline elements
  class Inline

    def tex_process
      case self.node_name
      #when 'inline_quoted'
      #  self.inline_quoted_process

      when 'inline_anchor'
        self.inline_anchor_process

      when 'inline_break'
        self.inline_break_process

      when 'inline_footnote'
        self.inline_footnote_process

      when 'inline_callout'
        self.inline_callout_process

      when 'inline_indexterm'
        self.inline_indexterm_process

      when 'inline_image'
        self.inline_image
      else
        self.text
      end
    end

    # NICOLAS
    def inline_image

      if self.attributes['width']
        width = self.attributes['width']
      elsif self.attributes['pdfwidth']
        width = self.attributes['pdfwidth']
      end

      if width
        if    width.include?("mm")
          width = "#{width.to_f}mm"
        elsif width.include?("cm")
          width = "#{width.to_f}cm"
        elsif width.include?("in")
          width = "#{width.to_f}in"
        elsif width.include?("%")
          width = "#{width.to_f/100}\\textwidth"
        else
          width = '\textwidth'
        end
      else
        width = '\textwidth'
      end

      raw_image = self.target  #self.attributes['target']
      if raw_image.nil_or_empty?
        puts "raw_image is nil"
      else
        unless (imagesdir = document.attr 'imagesdir').nil_or_empty?
          raw_image = ::File.join imagesdir, raw_image
        end  
      end

      if document.attributes['noteshare'] == 'yes'
        image_rx = /image.*original\/(.*)\?/
        match_data = raw_image.match image_rx
        if match_data
          image = match_data[1]
        else
          image = "undefined"
        end
      else
        image = raw_image
      end

      " \\includegraphics〈width=#{width}〉《#{self.image_uri self.target}》 "
    end


    #def inline_quoted_process
    #  # warn "THIS IS: inline_quoted_process: #{self.type}"  if $VERBOSE
    #  case self.type
    #    when :strong
    #      "\\textbf《#{self.text}》"
    #    when :emphasis
    #      "\\emph《#{self.text}》"
    #    when :asciimath
    #      output = Asciidoctor.convert( self.text, backend: 'html')
    #      output
    #    when :monospaced
    #      "\\texttt《#{self.text}》"
    #    when :superscript
    #      "$《》^{#{self.text}}$"
    #    when :subscript
    #      "$《》_{#{self.text}}$"
    #    when :mark
    #      "\\colorbox《yellow》《 #{self.text}》"
    #    when :double
    #      "``#{self.text}''"
    #    when :single
    #      "`#{self.text}'"
    #    when :latexmath
    #      "\\( #{self.text} \\)"
    #      # TODO: The formula is escaped and it should not
    #      #print self.text
    #      #"\\( #{LaTeX::TeXPostProcess.stem_substitutions self.text} \\)"
    #      # output = Asciidoctor.convert self.text, {stem: 'asciimath', backend: 'html'}
    #      #self.text
    #    when :unquoted
    #      result = ""
    #      role = self.attributes["role"]
    #      if $colors.include? role
    #        result << $tex.macro($colors[role], $tex.escape(self.text))
    #      else
    #        warn "This is inline_quoted_process.  I don't understand role = #{role}" if $VERBOSE
    #        result << $self.text
    #      end
    #      return result
    #    when :literal
    #      "\\texttt《#{self.text}》"
    #
    #    when :verse
    #      "\\texttt《#{self.text}》"
    #    else
    #      "\\unknown:#{self.type}\《#{self.text}\》"
    #  end
    #end

    def inline_anchor_process

      refid = self.attributes['refid']
      refs = self.parent.document.references[:ids]
      # FIXME: the next line is HACKISH (and it crashes the app when refs[refid]) is nil)
      # FIXME: and with the fix for nil results is even more hackish
      # if refs[refid]
      if !self.text && refs[refid]
        reftext = refs[refid].gsub('.', '')
        m = reftext.match /(\d*)/
        if m[1] == reftext
          reftext = "(#{reftext})"
        end
      else
        reftext = self.text
      end
      case self.type
        when :link
          $tex.macro 'href', self.target, self.text
        when :ref
          $tex.macro 'label', (self.id || self.target)
        when :xref
          $tex.macro 'hyperlink', refid.tex_normalize, reftext
        else
          # warn "!!".magenta if $VERBOSE
      end
    end

    def inline_break_process
      "#{self.text} \\\\"
    end

    def inline_footnote_process
      $tex.macro 'footnote', self.text
    end

    def inline_callout_process
      # warn "Please implement me! (inline_callout_process)".red if $VERBOSE
    end

    def inline_indexterm_process
      case self.type
      when :visible
        output = $tex.macro 'index', self.text
        output += self.text
      else
        $tex.macro 'index', self.attributes['terms'].join('!')
      end
    end

  end

  class Table
    def old_tex_process
      # # warn "This is Asciidoctor::Table, tex_process.  I don't know how to do that".yellow +  " (#{self.node_name})".magenta if $VERBOSE
      # table = Table.new self.parent, self.attributes
      n_rows = self.rows.body.count
      n_columns = self.columns.count
      alignment = (['c'] * n_columns).join('|')
      output = "\\begin《center》\n"
      output << "\\begin《tabular》《|#{alignment}|》\n"
      output << "\\hline\n"
      self.rows.body.each_with_index do |row, index|
        row_array = []
        row.each do |cell|
          if Array === (cell_content = cell.content)
            row_array << cell_content.join("\n")
          else
            row_array << cell_content
          end
        end
        output << row_array.join(' & ')
        output << " \\\\ \n"
      end
      output << "\\hline\n"
      output << "\\end{tabular}\n"
      output << "\\end{center}\n"
      "#{output}"
    end

    def get_cell_content(the_cell)
      
      if Array === the_cell.content
        # The content has not been "parsed", must escape special chars
        result = $tex.escape the_cell.content.join("\n")
      else
        # The content is already parsed, just copy it
        result = the_cell.content
      end
    end

    def multicol(width, fmt, content)
      if width.nil? || (width == 1)
        content
      else
        "\\multicolumn《#{width}》《#{fmt}》《#{content}》"
      end
    end

    def multirow(height, width, content)
      if height.nil? || (height == 1)
        content
      else
        "\\multirow《#{height}》《#{width}》《#{content}》"
      end
    end

    def debug_cell(cell)
      output = ""
      if cell.rowspan.nil?
        output << "rowspan = 1 "
      else
        output << "rowspan = #{cell.rowspan} "
      end

      if cell.colspan.nil?
        output << "colspan = 1 "
      else
        output << "colspan = #{cell.colspan} "
      end
  
      puts "#{output} " + self.get_cell_content(cell)
    end

    def get_table_width()
      table_width = 0
      self.columns.each do |onecol|
        table_width += onecol.attributes['width']
      end
      table_width
    end

    def get_columns_header(table_width)
      # DANGER HACK BY Nico
      # My LaTeX installation adds 0.4cm for each column which is 
      # about 2.5% of the page width (17cm in my template) so I
      # reduce the column width by 2.5cm each
      reduction = 0.025
      alignment = []
      self.columns.each do |onecol|
        width = onecol.attributes['width'].to_f / table_width - reduction
        width = width.round(3)
        alignment << "m{#{width}\\textwidth}"
      end
      alignment
    end

    def fill_array(the_array, x, y, dx, dy)
      maxY = y + dy
      maxX = x + dx
      sy   = y
      while y < maxY do
        tx = x
        while tx < maxX do
          # put 0 on the 1st line and put 1 on other lines
          if (y == sy)
            the_array[y][tx] = 0
          else
            the_array[y][tx] = ((x == tx) ? dx : 0)
          end
          tx = tx + 1
        end
        y = y + 1
      end
    end

    def tex_process_buggy_borders
      #-------------------------------------------------------------------------
      # NICOLAS TABLE LATEX
      # self.columns[0].attributes[] colnumber, width, halign, valign
      table_width = self.get_table_width()
      alignment = self.get_columns_header(table_width.to_f)
      alignment = alignment.join('|')

      output  = "\\begin《center》\n"
      output << "\\begin《tabular》《|#{alignment}|》\n"
      output << "\\hline\n"

      cols_nb = self.columns.count
      rows_nb = self.rows.body.count
      output_array = Array.new(rows_nb) { Array.new(cols_nb, 0)}

      # For each line in the table
      self.rows.body.each_with_index do |row, rowIdx|
        # Start in cell 0
        idx = 0

        row.each do |cell|
          while output_array[rowIdx][idx] != 0 do
            idx = idx + 1
          end

          rs = (cell.rowspan.nil? ? 1 : cell.rowspan);
          cs = (cell.colspan.nil? ? 1 : cell.colspan);
          self.fill_array(output_array, idx, rowIdx, cs, rs)
          output_array[rowIdx][idx] = cell
          idx += cs
        end # each cell in row

      end # each row in table

      output_array.each_with_index do |row, y|
        row_array = []
        rules = ""
        row.each_with_index do |cell, idx|
          if cell.is_a? Integer
            if cell == 0
              # skip the cell, because au colspan
            else
              # Empty cell because of rowspan
              row_array << self.multicol(cell, "|c|", " ")
            end
          else
            content = self.get_cell_content(cell)
            content = self.multirow(cell.rowspan, "*", content)
            row_array << self.multicol(cell.colspan, "|c|", content)
          end

          if output_array[y+1].nil?
            rules << "\\cline《#{idx+1}-#{idx+1}》 "
          else
            if output_array[y+1][idx].is_a? Integer
              if output_array[y+1][idx] == 0
                # skip the cell, because au colspan
                rules << "\\cline《#{idx+1}-#{idx+1}》 "
              end
            else
              rules << "\\cline《#{idx+1}-#{idx+1}》 "
            end
          end
        end

        output << row_array.join(" & \n")
        output << "\\\\"
        output << rules            #output << "\\hline"
        output << "\n\n"
      end

      output << "\\hline\n"
      output << "\\end{tabular}\n"
      output << "\\end{center}\n"
      "#{output}"
      #-------------------------------------------------------------------------
    end

    def tex_process
      #-------------------------------------------------------------------------
      # self.columns[0].attributes[] colnumber, width, halign, valign
      table_width = self.get_table_width()
      alignment = self.get_columns_header(table_width.to_f)
      alignment = alignment.join('|')

      output  = "\\begin《center》\n"
      output << "\\begin《tabular》《|#{alignment}|》\n"
      output << "\\hline\n"

      cols_nb  = self.columns.count
      rows_nb  = self.rows.body.count
      rowsinfo = Array.new(cols_nb) { "1/1"}   # RowSpan/ColSpan

      # For each line in the table
      self.rows.body.each_with_index do |row, y|
        row_array = []
        borders = ""
        x = 0

        # Foreach Cells in Row
        row.each do |cell|
          # Extract info from previous row
          old = rowsinfo[x].split('/')
          ors = old[0].to_i
          ocs = old[1].to_i

          # Previous row spans down
          if ors > 1
            ors -= 1
            rowsinfo[x] = "#{ors}/#{ocs}"
            row_array << self.multicol(ocs, "|c|", ' ') # Empty cell
            if ors == 1
              borders << "\\cline《#{x+1}-#{x+ocs}》 "
            end
            x += ocs   # Compute next cell x position (skip spanned columns)
          end

          # Current cell's span information
          rs = (cell.rowspan.nil? ? 1 : cell.rowspan);
          cs = (cell.colspan.nil? ? 1 : cell.colspan);

          # Add content to latex result
          content = self.get_cell_content(cell)
          content = self.multirow(rs, "*", content)
          row_array << self.multicol(cs, "|c|", content)

          # Save current cell info for the next row
          rowsinfo[x] = "#{rs}/#{cs}"
          if rs == 1
            borders << "\\cline《#{x+1}-#{x+cs}》 "
          end
          x += cs
        end # Foreach Cells in Row

        output << row_array.join(" & \n")
        output << " \\\\"
        output << " #{borders}"            #output << "\\hline"
        output << "\n\n"

      end # Foreach Rows in Table

      output << "\\hline\n"
      output << "\\end{tabular}\n"
      output << "\\end{center}\n"
      "#{output}"
      #-------------------------------------------------------------------------
    end
  end







  class OldTable
    def tex_process
      # # warn "This is Asciidoctor::Table, tex_process.  I don't know how to do that".yellow +  " (#{self.node_name})".magenta if $VERBOSE
      # table = Table.new self.parent, self.attributes
      n_rows = self.rows.body.count
      n_columns = self.columns.count
      alignment = (['c']*n_columns).join('|')
      output = "\\begin《center》\n"
      output << "\\begin《tabular》《|#{alignment}|》\n"
      output << "\\hline\n"
      self.rows.body.each_with_index do |row, index|
        row_array = []
        row.each do |cell|
          if Array === (cell_content = cell.content)
            row_array << cell_content.join("\n")
          else
            row_array << cell_content
          end
        end
        output << row_array.join(' & ')
        output << " \\\\ \n"
      end
      output << "\\hline\n"
      output << "\\end{tabular}\n"
      output << "\\end{center}\n"
      "#{output}"
    end
  end


  module LaTeX
    # TeXPostProcess cleans up undesired transformations
    # inside the TeX environment.  Strings
    # &ampp;, &gt;, &lt; are mapped back to
    # &, >, < and \\ is conserved.
    module TeXPostProcess

      def self.match_inline str
        rx_tex_inline = /\$(.*?)\$/
        str.scan rx_tex_inline
      end

      def self.match_block str
        rx_tex_block = /\\\[(.*?)\\\]/m
        str.scan rx_tex_block
      end

      def self.make_substitutions1 str
        str = str.gsub("&amp;", "&")
        str = str.gsub("&gt;", ">")
        str = str.gsub("&lt;", "<")
      end

      def self.make_substitutions_in_matches matches, str
        matches.each do |m|
          m_str = m[0]
          m_transformed = make_substitutions1 m_str
          str = str.gsub(m_str,m_transformed)
        end
        str
      end

      # (1) & (2) are needed together to protect \\
      # inside of matrices, etc.
      def self.make_substitutions str
        str = str.gsub('\\\\', '@@')   # (1)
        matches = match_inline str
        if matches.count > 0
          str = make_substitutions_in_matches matches, str
        end
        matches = match_block str
        if matches.count > 0
          str = make_substitutions_in_matches matches, str
        end
        str = str.tr('@','\\')         # (2)
        str
      end

      def self.stem_substitutions str
        str = str.gsub('\\\\', '@@')   # (1)
        str = make_substitutions1 str
        str = str.tr('@','\\')         # (2)
        str
      end


    end
  end
end
