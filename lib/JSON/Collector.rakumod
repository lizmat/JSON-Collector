use v6.*;  # want nano()

use JSON::Fast:ver<0.20.1+>:auth<zef:timo>;

#- JSON::Collector::Item -------------------------------------------------------
# Class to handle a single data item

class JSON::Collector::Item {
    has $.collector;
    has $.IO;
    has $.data handles <
      AT-KEY
      AT-POS
      iterator
      keys
      raku
      values
    >;

    method discard(JSON::Collector::Item:D:) {
        $!IO.unlink
    }

    method mark-as-processed(JSON::Collector::Item:D: Str() $type = "") {
        my $done = $!collector.done;
        if $done ~~ IO {
            my $io = $type ?? $done.add($type) !! $done;
            my $date = Date.today;
            $io = $io.add($date.year).add($date.yyyy-mm-dd);
            $io.mkdir;

            $io = $io.add(nano);
            # slurp and spurt instead of rename to avoid any cross-filesystem
            # issues
            return False unless $io.spurt($!IO.slurp);

            my $proc = run 'gzip', '-9', $io.absolute;
            return False if $proc.exitcode;
        }
        elsif $done ~~ Callable {
            return unless $done(self);
        }

        $!IO.unlink
    }
}

#- JSON::Collector -------------------------------------------------------------
# The actual collecting logic

class JSON::Collector {
    has IO() $.todo          is built(:bind) = "todo".IO;
    has      $.done          is built(:bind) = "done".IO;
    has Bool $.pretty        is built(:bind) = True;
    has Int  $.spacing       is built(:bind) = 2;
    has      $.sorted-keys   is built(:bind) = True;

    submethod TWEAK(--> Nil) {
        my @problems;
        @problems.push("$!todo.absolute() is not a directory")
          unless $!todo.d;
        @problems.push("Don't know how to handle processed items")
          unless ($!done ~~ IO && $!done.d)
            || $!done ~~ Callable
            || $!done =:= Nil;

        die "Found the following issues:\n  @problems.join("\n  ")"
          if @problems;
    }

    multi method store(JSON::Collector:D: Str:D $json --> Bool:D) {
        $!todo.add(nano).spurt($json)
    }
    multi method store(JSON::Collector:D: Any:D \data --> Bool:D) {
        $!todo.add(nano).spurt(
          to-json(
            data, :$!pretty, :$!spacing, :$!sorted-keys, |%_
          )
        )
    }

    method unprocessed(JSON::Collector:D: --> Seq:D) {
        $!todo.dir.map: {
            JSON::Collector::Item.new(
              :collector(self), :IO($_), :data(from-json(.slurp))
            )
        }
    }
}

# vim: expandtab shiftwidth=4
