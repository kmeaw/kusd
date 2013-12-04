class Bash
  token WORD ASGNWORD PIPE NEWLINE

rule
list		: command		{ result = [val[0]] }
		| list list_separator command { result = [*val[0], val[2]] }
list_separator	: NEWLINE
command		: pipeline
asgn_words	: /* none */		{ result = [] }
		| ASGNWORD WORD asgn_words	{ result = [[val[0], q(val[1])], *val[2]] }
simple		: asgn_words WORD arguments { result = {type: :exec, assign: val[0], word: q(val[1]), arguments: val[2] } }
arguments	: /* none */ { result = [] }
		| arguments WORD { result = [*val[0], q(val[1])] }
bang_or_none	: '!' { result = true }
		| /* none */ { result = false }
pipeline	: bang_or_none simple { result = [[val[0], val[1]]] }
		| pipeline PIPE bang_or_none simple { result = [*val[0], [val[2], val[3]]] }
---- header
# $Id$
require './bashlex'
---- inner

  def parse(str)
    @q = []
    lex = Lexer.new(str)
    lex.run { |q| @q << q }
    do_parse
  end

  def next_token
    @q.shift
  end

  def q(s)
    if s =~ /\A['"]/
      s = s[1 ... -1]
    else
      s
    end
  end

---- footer

if $PROGRAM_NAME == __FILE__
  require 'pp'
  parser = Bash.new
  pp parser.parse("POSIXLY_CORRECT=1 ls -l user* test.file")
  pp parser.parse("cat | shuf | head; for i in `ls *.txt`;do echo \"Foo $i has 5 \\$\"; echo bar | grep --color=auto 'a'; done # This is a comment")
end

