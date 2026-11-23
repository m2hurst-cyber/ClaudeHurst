module Capture
  # A tiny, safe evaluator for leg totals: numbers, references (kind.field, input.key,
  # totals.key), + - * /, parentheses, and max(), min(), round(), gt(). No Ruby is evaluated.
  # Operators need spaces around them ("a - b"), since document kinds contain hyphens.
  class Formula
    class Error < StandardError; end
    REF = /[a-z0-9][a-z0-9-]*\.[a-z_][a-z0-9_]*/ # a field always starts with a letter, so 0.9235 is a number
    TOKEN = /\s*(?:(?<fn>max|min|round|gt)\(|(?<ref>#{REF})|(?<num>\d+(?:\.\d+)?)|(?<op>[-+*\/(),]))/

    def self.refs(expr) = expr.to_s.scan(REF)

    def initialize(expr, &resolve)
      @tokens = tokenize(expr.to_s)
      @resolve = resolve
      @i = 0
    end

    def value
      v = expression
      raise Error, "unexpected #{@tokens[@i].inspect}" if @i < @tokens.size
      v
    end

    private

    def tokenize(s)
      out = []
      pos = 0
      while pos < s.length
        break if s[pos..].strip.empty?
        m = TOKEN.match(s, pos)
        raise Error, "can't read #{s[pos..].strip.inspect}" unless m && m.begin(0) == pos
        out << (m[:num] ? [:num, m[:num].to_f] : m[:fn] ? [:fn, m[:fn]] : m[:ref] ? [:ref, m[:ref]] : [:op, m[:op]])
        pos = m.end(0)
      end
      out
    end

    def peek = @tokens[@i]
    def take = @tokens[@i].tap { @i += 1 }
    def op?(c) = peek == [:op, c]

    def expression
      v = term
      while op?("+") || op?("-")
        o = take[1]
        v = o == "+" ? v + term : v - term
      end
      v
    end

    def term
      v = factor
      while op?("*") || op?("/")
        o = take[1]
        r = factor
        v = o == "*" ? v * r : (r.zero? ? 0.0 : v / r)
      end
      v
    end

    def factor
      t = take or raise Error, "unexpected end"
      case t[0]
      when :num then t[1]
      when :ref then @resolve.call(t[1]).to_f
      when :fn
        args = [expression]
        args << expression while op?(",") && take
        raise Error, "missing )" unless op?(")") && take
        case t[1]
        when "max" then args.max
        when "min" then args.min
        when "round" then args.first.round
        when "gt" then args[0] > args[1] ? 1.0 : 0.0
        end
      when :op
        if t[1] == "("
          v = expression
          raise Error, "missing )" unless op?(")") && take
          v
        elsif t[1] == "-" then -factor
        else raise Error, "unexpected #{t[1]}"
        end
      end
    end
  end
end
