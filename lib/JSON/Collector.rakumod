use v6.*;  # want nano()

use JSON::Fast:ver<0.20.1+>:auth<zef:timo>;

#- JSON::Collector::Item -------------------------------------------------------
# Class to handle a single data item

class JSON::Collector::Item {
    has $.collector is built(:bind);
    has $.IO        is built(:bind);
    has $.data      is built(:bind) handles <
      AT-KEY AT-POS iterator keys raku values
    >;

    method discard(JSON::Collector::Item:D:) {
        $!IO.unlink
    }

    method mark-as-processed(JSON::Collector::Item:D: *@dirs) {
        my $old  = $!IO;

        my $done = $!collector.done;
        if $done ~~ IO {
            my $date = Date.today;
            @dirs.append($date.year, $date.yyyy-mm-dd);

            my $dir = $done.add(@dirs);
            $dir.mkdir;

            my $new = $dir.add($old.basename);
            # slurp and spurt instead of rename to avoid any cross-filesystem
            # issues
            return False unless $new.spurt($old.slurp);

            my $proc = run 'gzip', '-9', $new.absolute;
            return False if $proc.exitcode;

            $!IO := $new.extension("gz");
        }
        elsif $done ~~ Callable {  # UNCOVERABLE
            return unless $done(self);
        }

        $old.unlink
    }
}

#- JSON::Collector -------------------------------------------------------------
# The actual collecting logic

class JSON::Collector {
    has IO() $.todo        = "todo".IO;
    has      $.done        = "done".IO;
    has Bool $.pretty      = True;
    has Int  $.spacing     = 2;
    has      $.sorted-keys = True;

    submethod TWEAK(--> Nil) {
        my @problems;

        @problems.push("$!todo.absolute() is not a directory")
          unless $!todo.d;

        if $!done ~~ IO {
            @problems.push("$!done.absolute() is not a directory")
              unless $!done.d;
        }
        else {
            @problems.push("Don't know how to handle processed items")
              unless $!done ~~ Callable
                  || $!done =:= Nil;
        }

        die "Found the following issues:\n  @problems.join("\n  ")"
          if @problems;
    }

    multi method store(JSON::Collector:D: Str:D $json --> IO::Path:D) {
        my $final := $!todo.add(nano);
        my $temp  := $final.extension("tmp");
        if $temp.spurt($json) {        # write the file
            if $temp.rename($final) {  # atomically put in place
                return $final;  # UNCOVERABLE
            }
        }

        Nil
    }
    multi method store(JSON::Collector:D: Any:D \data --> IO::Path:D) {
        self.store($_) with to-json(
          data, :$!pretty, :$!spacing, :$!sorted-keys, |%_
        )
    }

    method unprocessed(JSON::Collector:D: --> Seq:D) {
        $!todo.dir.map: {
            JSON::Collector::Item.new(
              :collector(self), :IO($_), :data(from-json(.slurp))
            ) unless .extension;
        }
    }
}

#- EXPORT ----------------------------------------------------------------------

my sub EXPORT() {
    BEGIN Map.new('&from-json' => &from-json, '&to-json' => &to-json)
}

# vim: expandtab shiftwidth=4
