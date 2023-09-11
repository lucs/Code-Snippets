unit class Code::Snippets;

# --------------------------------------------------------------------
my regex snal     { (<[\w]> <[\w.-]>*) };
my regex filename { <[\w.-]>+ };
my regex filepath { <[\w.-]> <[/\w.-]>* };

grammar Snalex::Grammar {
    token snalex    { <snal> [<filenamed> | <subdired>]? }
    token filenamed { ([ ':' | '::' ]) <filename>? }
    token subdired  { ([ '/' | '//' ]) <filepath>? }
}

class Snalob {...}

class Snalex::Actions {
    has $.the_snal;
    has $.main  = True;
    has $.path;
    method snalex ($/) {
        make Snalob.new(
            snalex => ~$/,
            snal => ~$<snal>,
            path => $.path // ~$<snal>,
            main => $.main,
        );
    }
    method snal ($/) {
        $!the_snal = ~$/;
    }
    method filenamed ($/) {
        $!main  = False if $0 eq '::';
        $!path = ~$<filename> if $<filename>;
    }
    method subdired ($/) {
        $!main  = False if $0.substr(0, 2) eq '//';
        if $<filepath> {
            $!path = "$!the_snal/" ~ ~$<filepath>;
            $!path ~= $!the_snal if ~$/.substr(*-1) eq '/';
        }
        else {
            $!path = "$!the_snal/$!the_snal";
        }
    }
}

# --------------------------------------------------------------------
class Snalob {
    has Str $.snalex;
    has Str $.snal;
    has Str $.path;
    has Bool $.main;

    method from-str (Str $snalex) {
        my $snalex-parsed = Snalex::Grammar.parse(
            $snalex,
            rule => 'snalex',
            :actions(Snalex::Actions.new),
        );
        return $snalex-parsed ?? $snalex-parsed.ast !! Nil;
    }
}

# --------------------------------------------------------------------
class Snip {
    has Snalob $.snalob,
    has Str    $.bef,
    has Str    $.txt,
    has Str    $.aft,

    method build (
        $bef,
        $txt,
        $aft,
        $snalex_ʀ,
    ) {
        my $snalex = ~($bef ~~ / <$snalex_ʀ> /);
        my $snalob = Snalob.from-str($snalex) orelse
          return False, "Invalid snippet alias expression '$snalex'.";
        return True, self.bless:
            :$snalob,
            :$bef,
            :$txt,
            :$aft,
        ;
    }
}

# --------------------------------------------------------------------
    #|{
        snips %
            $snal %
                Snip @

    }
has %.snips;

has @.errors;

    #|{The file that was used to read snippets.}
has $.snips-file = "";

    #|{The directory in which the extracted snippets will reside.}
has $.snips-dir = "";

# --------------------------------------------------------------------
method add-snip (Snip $snip) {
    my $snal = $snip.snalob.snal;
    my $path = $snip.snalob.path;
    $snal !~~ $.snips or
     $path !~~ $.snips{$snal} or
     return False, "Path '$path' already exists for snippet alias '$snal'.";
    $.snips{$snal}.push: $snip;
    return True, Nil;
}

# --------------------------------------------------------------------
method build (
    Regex   :$snip-bef_ʀ,
    Regex   :$snalex_ʀ,
    Regex   :$snip-aft_ʀ,
    Str     :$snips-dir = "/tmp",
    Str     :$snips-file,
) {
    return False, "Can't read '$snips-file'." unless $snips-file.IO.f;
    my %snips;
    my $self = Code::Snippets.new(:$snips-dir, :$snips-file, :%snips);
    my $snips-text = slurp($snips-file);
    $snips-text.comb(
        /
            $<snip-bef> = [$snip-bef_ʀ .*? \n ]
            $<snip-txt> = .*?
            $<snip-aft> = <before [$snip-aft_ʀ \n] | $snip-bef_ʀ | $>
        /, :match
    ).map({
        my ($ok-snip, $snip) = Code::Snippets::Snip.build(
            ~.<snip-bef>,
            ~.<snip-txt>,
            ~.<snip-aft>,
            $snalex_ʀ,
        );
        $ok-snip or $self.errors.push($snip), next;
        my $snal = $snip.snalob.snal;
        next if $snal eq 'SKIP';
        last if $snal eq 'STOP';
        my ($ok-add, $got-add) = $self.add-snip($snip);
        $ok-add or $self.errors.push($got-add);
    });
    return True, $self;
}

# --------------------------------------------------------------------
method list-snals () {
    self.snips.keys.sort;
}

method list-paths (Str $snal) {
    self.snips{$snal}.keys.sort;
}

    #|{
    Extracts the requested snal snippets to disk. Throws an exception
    if unable to.
    }
method extract ($snal-want) {
    for %.snips.keys -> $snal-got {
        next unless $snal-got eq $snal-want;
        for %.snips{$snal-want}.list -> $snip {
            my $path = $.snips-dir ~ "/" ~ $snip.snalob.path;
            $path.IO.dirname.IO.mkdir;
            $path.IO.spurt: .bef ~ .txt given $snip;
        }
    }

}

