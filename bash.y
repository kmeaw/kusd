class Bash
  token WORD ASGNWORD EOF BACKTICK DQUOTE ENDDQUOTE VAR SQUOTE

prechigh
  left '&' ';' "\n" EOF
  left '&&' '||'
  right '|' '|&'
preclow

start inputunit

rule
inputunit	: simple_list simple_list_terminator		{ @result = val[0]; yyaccept }
		| "\n"						{ result = :xx; yyaccept }
		| EOF						{ yyerror }
simple_list_terminator	: "\n"					{ result = :xx }
			| EOF					{ result = :yy }
simple_list	: simple_list1
		| simple_list1 '&'
		| simple_list1 ';'
simple_list1	: simple_list1 '&&' newline_list simple_list1	{ result = {type: :flow, op: val[1], car: val[0], cdr: val[3]} }
		| simple_list1 '||' newline_list simple_list1	{ result = {type: :flow, op: val[1], car: val[0], cdr: val[3]} }
		| simple_list1 '&' simple_list1			{ result = dolist(:list, {type: :bg, value: val[0]}, val[3]) }
		| simple_list1 ';' simple_list1			{ result = dolist(:list, val[0], val[3]) }
		| pipeline_command
pipeline_command :
		  pipeline
		| '!' pipeline_command				{ result = {type: :not, value: val[1]} }
		| '!' list_terminator				{ result = {type: :exec, asgn: [], car: "false", cdr: []} }
pipeline	: pipeline '|' newline_list pipeline		{ result = dolist(:pipe, val[0], val[3]) }
		| pipeline '|&' newline_list pipeline		{ result = dolist(:pipe, {type: :wrap_stderr, value: val[0]}, val[3]) }
		| command
newline_list	: /* none */
		| newline_list "\n"				{ result = :xx } 
command		: simple_command				
		| shell_command
simple_command	: assignations simple_command_element simple_command_elements	{ result = {type: :exec, asgn: val[0], car: val[1], cdr: val[2]} }
		| ASGNWORD WORD assignations					{ result = {type: :let, asgn: [{type: :assign, key: val[0], value: val[1]}, *val[2]]} }
assignations	: /* empty */					{ result = [] }
		| ASGNWORD WORD assignations				{ result = [{type: :assign, key: val[0], value: val[1]}, *val[2]] }
simple_command_element : # XXX: do string expansion here
		  WORD		{ result = {type: :lit, value: val[0]} }
		| SQUOTE	{ result = {type: :lit, value: squote(val[0])} }
		| DQUOTE quoted ENDDQUOTE	{ result = {type: :str, values: val[1]} }
		| BACKTICK	{ result = {type: :backtick, value: Bash.new.setq(val[0]).each} }
quoted		: /* empty */		{ result = [] }
		| BACKTICK quoted	{ result = [{type: :backtick, value: Bash.new.setq(val[0]).each}, *val[1]] }
		| WORD quoted		{ result = [{type: :lit, value: val[0]}, *val[1]] }
		| VAR quoted		{ result = [{type: :var, value: val[0][1..-1]}, *val[1]] }
simple_command_elements : /* empty */				{ result = [] }
		| word_list
list_terminator	: "\n"		{ result = :xx }
		| ";"		{ result = :zz }
		| EOF		{ result = :yy }
shell_command	: for_command
		| if_command
		| group_command
		| subshell
word_list	: simple_command_element simple_command_elements	{ result = [val[0], *val[1]] }
subshell	: '(' compound_list ')'	{ result = {type: :fork, value: val[1]} }
for_command	: "for" WORD newline_list "in" word_list list_terminator newline_list "do" compound_list "done"	{ result = {type: :for, var: val[1], list: val[4], value: val[8]} }
if_command	: "if" compound_list "then" compound_list "fi"	{ result = {type: :if, cond: val[1], then: val[3]} }
		| "if" compound_list "then" compound_list "else" compound_list "fi"	{ result = {type: :if, cond: val[1], then: val[3], else: val[5] } }
		| "if" compound_list "then" compound_list elif_clause "fi"	{ result = {type: :if, cond: val[1], then: val[3], else: val[4] } }
elif_clause	: "elif" compound_list "then" compound_list	{ result = {type: :if, cond: val[1], then: val[3]} }
		| "elif" compound_list "then" compound_list "else" compound_list	{ result = {type: :if, cond: val[1], then: val[3], else: val[5] } }
		| "elif" compound_list "then" compound_list elif_clause	{ result = {type: :if, cond: val[1], then: val[3], else: val[4] } }
group_command	: '{' compound_list '}'	{ result = val[1] }
compound_list	: list
		| newline_list list1		{ result = val[1] }
list		: newline_list list0		{ result = val[1] }
list0		: list1 "\n" newline_list	{ result = dolist(:list, val[0], val[2]) }
		| list1 '&' newline_list	{ result = dolist(:list, {type: :bg, value: val[0]}, val[2]) }
		| list1 ';' newline_list	{ result = dolist(:list, val[0], val[2]) }
list1		: list1 '&&' newline_list list1	{ result = {type: :flow, op: val[1], car: val[0], cdr: val[3]} }
		| list1 '||' newline_list list1	{ result = {type: :flow, op: val[1], car: val[0], cdr: val[3]} }
		| list1 '&' newline_list list1	{ result = dolist(:list, {type: :bg, value: val[0]}, val[3]) }
		| list1 ';' newline_list list1	{ result = dolist(:list, val[0], val[3]) }
		| list1 "\n" newline_list list1	{ result = dolist(:list, val[0], val[3]) }
		| pipeline_command

---- header
# $Id$
require './bashlex'
---- inner

  def load(str)
    q = []
    lex = Lexer.new(str)
    lex.run { |qe| q << qe }
    setq q
  end

  def setq(qs)
    @q = qs
    self
  end

  def squote(s)
    s[1 ... -1]
  end

  def next_token
    n = @q.shift
    n
  end

  def dolist(kind, car, cdr)
    if cdr.is_a?(Hash) and cdr[:type] == kind
      {type: kind, values: [car, *cdr[:values]].compact}
    elsif car.is_a?(Hash) and car[:type] == kind
#      raise RuntimeError, "wtf: #{car.inspect} : #{cdr.inspect}"
      {type: kind, values: [*car[:values], cdr]}
    else
      {type: kind, values: [car, cdr].compact}
    end
  end

  def parse(str)
    load(str)
    do_parse
  end

  def next
    while true
      break if @q[0].nil?
      break if @q[0][0] == :EOF
      do_parse
      break if @result.nil?
      yield @result unless @result == "\n"
    end
    raise StopIteration
  end

  def each(*a,&b)
    if b
      begin
        self.next { |u| b.call(u) } while true 
      rescue StopIteration
      end
    else
      units = []
      begin
	self.next { |u| units << u } while true
      rescue StopIteration
      end
      units.each(*a,&b)
    end
  end

---- footer

def unparse(exp)
  case exp
  when Array, Enumerator
    exp.map{|x| unparse(x)}.join(' ')
  when Hash
    case exp[:type]
    when :lit
      "\"#{exp[:value]}\""
    when :exec
      (
        exp[:asgn].map{|e| unparse(e)} +	# list of "assign"s
	[exp[:car][:value]] +
	exp[:cdr].map{|e| unparse(e)}		# list of "lit/backtick"s
      ).join(' ')
    when :not
      "! " + unparse(exp[:value])
    when :var
      "${#{exp[:value]}}"
    when :str
      exp[:values].map{|e| unparse(e)}.join
    when :assign
      exp[:key] + exp[:value]
    when :list
      exp[:values].reject{|x| x =~ /^\s*$/}.map{|e| unparse(e)}.join(" ; ")
    when :pipe
      exp[:values].map{|e| unparse(e)}.join(" | ")
    when :simple
      unparse(exp[:value])
    when :backtick
      "$( #{unparse(exp[:value])} )"
    when :fork
      "(#{unparse(exp[:value])})"
    when :for
      "for #{exp[:var]} in #{exp[:list].map{|x| unparse(x)}.join(' ')} do ; #{unparse exp[:value]} ; done"
    when :let
      exp[:asgn].map{|e| unparse(e)}.join(" ")
    else
      raise NotImplementedError, exp.inspect
    end
  when NilClass
    ""
  else
    raise NotImplementedError, exp.inspect
  end
end

if $PROGRAM_NAME == __FILE__
  require 'pp'
  parser = Bash.new
  program = <<-EOF
#!/bin/sh
    cat | shuf | head 
    special
    z=0 n=0
    ( a ; b ) | ( c
    d )
    for i in `ls *.txt` ; do 
      echo "Foo $i has $(get_bucks $i) \\$"
      echo $(get_bucks $i)
      echo bar | POSIXLY_CORRECT=1 grep --color=auto 'a'
      ! test -d "$i"
    done # This is a comment
    exit 0
  EOF
  program = "a --arg value | b | c"
  parser.load(program)
  parser.each do |parsed|
    pp parsed
    puts unparse( parsed )
    puts "--"
  end
end
