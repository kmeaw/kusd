require 'strscan'
class Lexer
  attr_reader :str

  def initialize(str)
    @str = StringScanner.new str
  end

  def op?(str)
    (not str.empty?) and OPS.detect{|k,v| v.start_with? str}
  end

   TOKENS = {
        root: [
            [:NEWLINE, /[;\n]/m],
	    [:PIPE, /[|]/],
            [:keyword, /\$\(\(/, :math],
            [:keyword, /\$\(/, :paren],
            [:keyword, /\${#?/, :curly],
            [:backtick, /`/, :backticks],
        #'basic': [
	    [:SPACE, /#.*\n/],
	    [:escape, /\\[\w\W]/],
	    [:ASGNWORD, /(\b\w+)(\s*)(=)/],
#	    [:operator, /[\[\]{}()=]/],
	    [:here, /<<</],
	    [:operator, /&&|\|\|/],
        #'data': [
            [:WORD, /\$?"(\\\\|\\[0-7]+|\\.|[^"\\])*"/],
            [:WORD, /\$?'(\\\\|\\[0-7]+|\\.|[^'\\])*'/],
	    [:SPACE, /[ \t]+/],
            [:WORD, /[^\s{}|();\n$"\'`\\<]+/],
            [:number, /\d+(?= |\Z)/],
            [:variable, /\$#?(\w+|.)/],
            [:WORD, /</]
        ],
        curly: [
	    [:keyword, /}/, :pop],
	    [:keyword, /:-/],
	    [:varname, /[a-zA-Z0-9_]+/],
	    [:punct, /[^}:"'`$]+/],
	    [:punct, /:/],
        ],
        paren: [
	    [:keyword, /\)/, :pop]
        ],
        math: [
	    [:keyword, /\)\)/, :pop],
            [:operator, /[-+*\/%^|&]|\*\*|\|\|/],
	    [:number, /\d+/]
        ],
        backticks: [
	    [:endbacktick, /`/, :pop]
        ],
    }

  def run
    mode = :root
    modestack = []
    until @str.eos?
      text, type, match, switch = nil
      if mode == :root
	tokens = TOKENS[:root]
      else
	tokens = TOKENS[mode] + TOKENS[:root]
      end
      for entry in tokens
	type, match, switch = entry
	break if text = @str.scan(match)
      end
      if text
	if type == :SPACE or mode == :backticks or type == :backtick
#	  yield [type, mode, text]
	else
	  yield [type, text] 
	end
	if switch == :pop
	  mode = modestack.pop
	elsif switch
	  modestack.push mode
	  mode = switch
	end
      else
        x = @str.getch
        yield [x, x]
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  lex = Lexer.new("foo | bar | baz; for i in `ls *.txt`;do echo \"Foo $i has 5 \\$\"\necho bar | grep --color=auto 'a'; done # This is a comment")
  lex.run { |q| p q; puts caller[1].split(':')[1] }
end

