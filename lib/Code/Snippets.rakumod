unit class Code::Snippets;

# --------------------------------------------------------------------
my regex snal     { (<[\w]> <[\w.-]>*) };
my regex filename { <[\w.-]>+ };
my regex filepath { <[\w.-]> <[/\w.-]>* };

grammar Snalex::Grammar {
    token spec {
        <mods> <snal> [<filenamed> | <subdired>]?
    }
    token mods {
        (<[.-]> ** 0..2)
        <?{
            ($0.chars < 2) || do {
                my $m = $0;
                so($m ~~ /'-'/ && $m ~~ /'.'/);
            }
        }>
    }
    token filenamed { ([ ':' | '::' ]) <filename>? }
    token subdired  { ([ '/' | '//' ]) <filepath>? }
}

class Snalob {...}

class Snalex::Actions {
    has $.the_snal;
    has $.keep-idl = True;
    has $.add-ext  = True;
    has $.main  = True;
    has $.file;
    method spec ($/) {
        make Snalob.new(
            snalex => ~$/,
            snal => ~$<snal>,
            file => $.file // ~$<snal>,
            add-ext => $.add-ext,
            keep-idl => $.keep-idl,
            main => $.main,
        );
    }
    method mods ($/) {
        $!add-ext  = False if index(~$/, '.').defined;
        $!keep-idl = False if index(~$/, '-').defined;
    }
    method snal ($/) {
        $!the_snal = ~$/;
    }
    method filenamed ($/) {
        $!main  = False if $0 eq '::';
        $!file = ~$<filename> if $<filename>;
    }
    method subdired ($/) {
        $!main  = False if $0.substr(0, 2) eq '//';
        if $<filepath> {
            $!file = "$!the_snal/" ~ ~$<filepath>;
            $!file ~= $!the_snal if ~$/.substr(*-1) eq '/';
        }
        else {
            $!file = "$!the_snal/$!the_snal";
        }
    }
}

# --------------------------------------------------------------------
class Snalob {
    has Str $.snalex;
    has Str $.snal;
    has Str $.file;
        # Add file extension to file name.
    has Bool $.add-ext;
        # Keep the ID lines in the extracted snippet.
    has Bool $.keep-idl;
    has Bool $.main;

    method from-str (Str $snalex) {
        my $snalex-parsed = Snalex::Grammar.parse(
            $snalex,
            rule => 'spec',
            :actions(Snalex::Actions.new),
        );
        return $snalex-parsed ?? $snalex-parsed.ast !! Nil;
    }
}

# --------------------------------------------------------------------
class Snip {
    has Str $.snal;
        # Extension will already have been added or not.
    has Str $.path;
        # ID lines will already have been stripped or not.
    has Str $.text;
    has Bool $.main;

    method build (
        Str $text is copy,
        Regex $snim,
        Str :$file-ext = "",
        Block :$fix-text = sub ($t) { $t },
    ) {
        $text ~~ / ^ $snim <blank>+ $<snalex>=(\S+) / orelse return False,
          "Incorrect snippet marker or missing snippet alias expression.";
        my $snalex = ~$<snalex>;
        my $snalob = Snalob.from-str($snalex) orelse
          return False, "Invalid snippet alias expression '$snalex'.";
        my $path = $snalob.file;
        $path ~= $file-ext if $snalob.add-ext;
        $text ~~ s/ $snim <blank>+ \S+ .*? \n+ // unless $snalob.keep-idl;
        $text = $fix-text.($text);
        return True, self.bless(
            snal => $snalob.snal,
            :$path,
            :$text,
            main => $snalob.main,
        );
    }
}

# --------------------------------------------------------------------
    #|{

    snips %
        $snal %
            $path %
                text Str
                main Bool

    }
has %.snips;

has @.errors;

    #|{The file that was used to read snippets.}
has $.snips-file = "";

    #|{The directory in which the extracted snippets will reside.}
has $.snips-dir = "";

# --------------------------------------------------------------------
method add-snip (Snip $snip) {
    my $snal = $snip.snal;
    my $path = $snip.path;
    $snal !~~ $.snips or
     $path !~~ $.snips{$snal} or
     return False, "Path '$path' already exists for snippet alias '$snal'.";
    $.snips{$snal}{$path}<text> = $snip.text;
    $.snips{$snal}{$path}<main> = $snip.main;
    return True, Nil;
}

# --------------------------------------------------------------------
method build (
    Regex   :$snim,
    Str     :$snips-dir = "/tmp",
    Str     :$snips-file,
    Str     :$file-ext = "",
    Block   :$fix-text = sub ($t) { $t },
) {
    return False, "Can't read '$snips-file'." unless $snips-file.IO.f;
    my %snips;
    my $self = Code::Snippets.new(:$snips-dir, :$snips-file, :%snips);
    my $snips-text = slurp($snips-file);
    $snips-text.comb(
        / $<snip-text>=[$snim \s+ .*?] <before $snim | $> /, :match
    ).map({
        my ($ok-snip, $got-snip) = Code::Snippets::Snip.build(
            ~.<snip-text>, $snim, :$file-ext, :$fix-text,
        );
        $ok-snip or $self.errors.push($got-snip), next;
        my $snal = $got-snip.snal;
        next if $snal eq 'SKIP';
        last if $snal eq 'STOP';
        my ($ok-add, $got-add) = $self.add-snip($got-snip);
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
method extract ($snal) {
    $snal.defined or do {
        note "No snippet alias to extract.";
        exit 1;
    }
    my @paths = %.snips{$snal}.keys.sort;
    if @paths.elems == 0 {
        note "No such ｢$snal｣ snippet alias in ｢{$.snips-file}｣.";
        exit 1;
    }
    for @paths -> $path {
        my $file = $.snips-dir ~ "/" ~ $path;
        $file.IO.dirname.IO.mkdir;
        spurt($file, %.snips{$snal}{$path}<text>);
    }
}

