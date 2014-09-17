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
            [nil, /[;\n]/m],
	    [nil, /[|]/],
            [:keyword, /\$\(\(/, :math],
            [:BACKTICK, /\$\(/, :paren],
            [:keyword, /\${#?/, :curly],
            [:BACKTICK, /`/, :backticks],
        #'basic': [
	    [:SPACE, /#.*/],
	    [:escape, /\\[\w\W]/],
	    [:ASGNWORD, /(\b\w+)(\s*)(=)/],
#	    [:operator, /[\[\]{}()=]/],
	    [:here, /<<</],
	    [:operator, /&&|\|\|/],
        #'data': [
            [:DQUOTE, /"/, :dquote],
            [:SQUOTE, /'(\\\\|\\[0-7]+|\\.|[^'\\])*'/],
	    [:SPACE, /[ \t]+/],
            [:WORD, /[^\s{}|();\n$"\'`\\<]+/],
            [:number, /\d+(?= |\Z)/],
            [:WORD, /\$#?(\w+|.)/],
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
	    [:ENDBACKTICK, /\)/, :pop]
        ],
        math: [
	    [:keyword, /\)\)/, :pop],
            [:operator, /[-+*\/%^|&]|\*\*|\|\|/],
	    [:number, /\d+/]
        ],
        backticks: [
	    [:ENDBACKTICK, /`/, :pop]
        ],
	dquote: [
	    [:ENDDQUOTE, /"/, :pop],
            [:BACKTICK, /\$\(/, :paren],
            [:BACKTICK, /`/, :backticks],
	    [:VAR, /[$][a-zA-Z0-9_]+/],
	    [:WORD, /([^"$`\\]|\\.)+/],
	],
    }

  SPECIALS = %w|
    if then else elif fi case esac for select while until do done in function time { } ! [[ ]] coproc
  |

  RESTART = %W[
    \n ; ( ) | & { } && ! |& do elif else if || ;; then time coproc until while
  ] + [nil]

  def run
    prev_tokens = []
    simple_run do |token|
      if token.first == :WORD
	if token.last == "in" and prev_tokens[-1].first == :WORD and prev_tokens[-2].first == "for"
  	  token = ["in", "in"]
	elsif token.first == :WORD and prev_tokens.last and RESTART.include?(prev_tokens.last.last) and SPECIALS.include?(token.last)
	  token = [token.last, token.last]
	end
      end

      yield token

      prev_tokens.push token
      prev_tokens.shift if prev_tokens.size > 2
    end
  end

  def simple_run
    mode = :root
    backtick = []
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
	if type == :SPACE # or mode == :backticks or type == :backtick
#	  yield [type, mode, text]
	elsif type == :ENDBACKTICK
	  backtick << [:EOF, false]
	  yield [:BACKTICK, backtick]
	  backtick = []
	else
	  if [:backticks, :paren].include? mode
	    backtick << [(type or text), text]
	  else
	    yield [(type or text), text] unless type == :BACKTICK
	  end
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
    yield [:EOF, false]
  end
end

if $PROGRAM_NAME == __FILE__
  lex = Lexer.new("foo | bar | baz; for i in `ls *.txt`;do echo \"Foo $i has 5 \\$\"\necho bar | grep --color=auto 'a'; done # This is a comment")
  lex.run { |q| p q; puts caller[1].split(':')[1] }
end

