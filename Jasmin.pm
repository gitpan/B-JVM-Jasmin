
package B::JVM::Jasmin;

use strict;
use vars qw(@pending_ops @pending_vals @pending_math @asm %symbols $current_id
            $PREAMBLE $POSTAMBLE $label_id @labels $VERSION);
$VERSION = '0.01';

my %JVM_OPS = ( add      => 'iadd',
                concat   => 'concat',
                multiply => 'imul',
                gt       => 'ifgt',
                and      => 'if',
                print    => 'print');

@labels = ();
%symbols = ();
$current_id = 0;
$label_id = 0;
my @parents = ();
my $op_count = 0;
use B qw(peekop class walkoptree_slow walkoptree_exec
         main_start main_root cstring svref_2object);
use B::Asmdata qw(@specialsv_name);

# seems to be needed to find a parent from a GV
sub find_parent {

    foreach (@parents) {
        if ($_->name ne 'null') {
            return $_->name;
        }
    }
}

sub mywalk {

    my($op, $method, $level) = @_;
    $op_count++; # just for statistics
    $level ||= 0;
    #warn(sprintf("walkoptree: %d. %s\n", $level, peekop($op))) if $debug;

    my $pre_method  = "pre_$method";
    my $post_method = "post_$method";

    my $pre  = $op->$pre_method($level);
    my $post = $op->$post_method($level);

    print ASM $pre;

    # If this operator has kids.
    #
    if ($$op && ($op->flags & B::OPf_KIDS)) {

        #print indent($level), "OP is ", $op->name, "\n";

        my $kid;
        unshift(@parents, $op);

        for ($kid = $op->first; $$kid; $kid = $kid->sibling) {

            #print indent($level), "kid is ", $kid->name, "\n";
            mywalk($kid, $method, $level + 1);

        }
        shift @parents;
    }
    print ASM $post;
}

sub get_new_label {
    $label_id++;
    return "J$label_id";
}
sub get_var_id {
    my $name = shift;
    unless ( $symbols{$name} ) {
        $current_id++;
        $symbols{$name} = $current_id;
    }
    return $symbols{$name};
}

sub terse {
    my ($cvref) = @_;
    my $cv = svref_2object($cvref);
    mywalk($cv->ROOT, "terse");
}

sub compile {
    my $classname = shift;
    my @options = @_;
    if (@options) {
        return sub {
            my $objname;
            foreach $objname (@options) {
                $objname = "main::$objname" unless $objname =~ /::/;
                eval "terse(\\&$objname)";
                die "terse(\\&$objname) failed: $@" if $@;
            }
        }
    } else {
        return sub { 
                open (ASM, ">${classname}.asm") 
                  or die "Could not open ${classname}.asm: $!";
                print ASM ".class public $classname\n";
                print ASM $PREAMBLE, "\n";

                mywalk(main_root, "emit") ;

                print ASM $POSTAMBLE, "\n";
                close ASM;
        }
    }
}

sub indent {
    my $level = shift;
    return "    " x $level;
}

sub B::OP::pre_emit {

    my ($op, $level, $label) = @_;
    my $jvm_op = $JVM_OPS{$op->name};

    if ($jvm_op eq 'print') {
        return "getstatic java/lang/System/out Ljava/io/PrintStream;\n";
    }
    if ($jvm_op eq 'if') {
        print "entering IF...\n";
        push @labels, get_new_label();
    }
    return "";

}

sub B::OP::post_emit {

    my ($op, $level, $label) = @_;
    my $jvm_op = $JVM_OPS{$op->name};

    if ($jvm_op eq 'ifgt') {
        my $label = pop @labels;
        return "isub\nifle $label\n";
    } elsif ($jvm_op eq 'if') {
        my $label = $labels[$#labels];
        return "$label:\n";
    } elsif ($jvm_op eq 'concat') {
        return "invokevirtual java/lang/String/concat(Ljava/lang/String;)" .
                      "Ljava/lang/String;\n";

    } elsif ($jvm_op eq 'print') {
        return "invokevirtual java/io/PrintStream/print(Ljava/lang/String;)V\n";

    } else {
        if ($jvm_op) {
            return "$jvm_op\n";
        }
    }
    return "";
}

sub B::SVOP::pre_emit {
    my ($op, $level) = @_;
    return $op->sv->pre_emit(0);
}
sub B::SVOP::post_emit {
    my ($op, $level) = @_;
    return $op->sv->post_emit(0);
}

sub B::GVOP::pre_emit {
    my ($op, $level) = @_;
    return $op->gv->pre_emit(0);
}
sub B::GVOP::post_emit {
    my ($op, $level) = @_;
    return $op->gv->post_emit(0);
}

sub B::PMOP::pre_emit {
    my ($op, $level) = @_;
    my $precomp = $op->precomp;
    return "";
}

sub B::PMOP::post_emit {
    my ($op, $level) = @_;
    my $precomp = $op->precomp;
    return "";
}

sub B::PVOP::pre_emit {
    my ($op, $level) = @_;
    return "";
}

sub B::PVOP::post_emit {
    my ($op, $level) = @_;
    return "";
}

sub B::COP::pre_emit {
    my ($op, $level) = @_;
    #my $label = $op->label;
    #if ($label) {
    #    $label = " label ".cstring($label);
    #}

    # This is the end of a statement.
    #
    if ($op->name eq 'nextstate') {
    }
    return "";
}

sub B::COP::post_emit {
    my ($op, $level) = @_;
    #my $label = $op->label;
    #if ($label) {
    #    $label = " label ".cstring($label);
    #}

    # This is the end of a statement.
    #
    if ($op->name eq 'nextstate') {
    }
    return "";
}

sub B::PV::pre_emit {
    my ($sv, $level) = @_;

    if (class($sv) eq 'PV') {
            return 'ldc ' . cstring($sv->PV) . "\n";
    }
    return "";
}
sub B::PV::post_emit {
    my ($sv, $level) = @_;
    return "";
}

sub B::AV::pre_emit {
    my ($sv, $level) = @_;
    return "";
}
sub B::AV::post_emit {
    my ($sv, $level) = @_;
    return "";
}

sub B::GV::pre_emit {
    my ($gv, $level) = @_;
    my $retval = "";
    my $stash = $gv->STASH->NAME;
    if ($stash eq "main") {
        $stash = "";
    } else {
        $stash = $stash . "::";
    }

    my $parent = find_parent();

    #print "I'm in a ", class($gv), ", and the parent is $parent\n";
    if (class($gv) eq 'GV' and $parent ne 'sassign') {

        $retval .= "iload_" . get_var_id($gv->NAME) . "\n";

        # fixme - only handles direct parent
        if ($parent eq 'concat') {
            $retval .= "invokestatic java/lang/String/valueOf(I)" .
                       "Ljava/lang/String;\n";
        }
    }
    return $retval;
}

sub B::GV::post_emit {
    my ($gv, $level) = @_;
    my $stash = $gv->STASH->NAME;
    if ($stash eq "main") {
        $stash = "";
    } else {
        $stash = $stash . "::";
    }

    my $parent = find_parent();

    #print "I'm in a ", class($gv), ", and the parent is $parent\n";
    if (class($gv) eq 'GV' and $parent eq 'sassign') {
        return "istore_" . get_var_id($gv->NAME) . "\n";
    }
    return "";
}

sub B::IV::pre_emit {
    my ($sv, $level) = @_;

    # Push a constant value onto the stack. Limited to integers
    # right now.
    #
    if (class($sv) eq 'IV') {
            return 'sipush ' . $sv->IV . "\n";
    }
    return "";
}

sub B::IV::post_emit {
    my ($sv, $level) = @_;
    return "";
}

sub B::NV::pre_emit {
    my ($sv, $level) = @_;
    return "";
}

sub B::NV::post_emit {
    my ($sv, $level) = @_;
    return "";
}

sub B::NULL::pre_emit {
    my ($sv, $level) = @_;
    return "";
}

sub B::NULL::post_emit {
    my ($sv, $level) = @_;
    return "";
}
    
sub B::SPECIAL::pre_emit {
    my ($sv, $level) = @_;
    return "";
}
sub B::SPECIAL::post_emit {
    my ($sv, $level) = @_;
    return "";
}

$PREAMBLE = <<EOF;
.super java/lang/Object

.method public <init>()V
    aload_0
    invokenonvirtual java/lang/Object/<init>()V
    return
.end method

.method public static main([Ljava/lang/String;)V
    .limit stack 12
    .limit locals 12
EOF

$POSTAMBLE = <<EOF;
    return
.end method
EOF

1;
__END__

=head1 NAME

B::JVM::Jasmin - Jasmin backend for the Perl compiler.

=head1 SYNOPSIS

  perl -MO=JVM::Jasmin,CLASSNAME perl_program.pl
  jasmin CLASSNAME.asm
  java CLASSNAME

=head1 DESCRIPTION

This module is a crude JVM backend for the Perl compiler. It aspires to be a
"proof of concept," but I think it does not even achieve that.  It's close,
though, and I think it might encourage people to explore this a little further.

=head1 AUTHOR

Brian Jepson, C<bjepson@as220.org>

Based on stuff in various B::* modules, by Malcolm Beattie,
C<mbeattie@sable.ox.ac.uk>

This is free software. You may distribute it under the same terms 
as Perl itself.

=head1 SEE ALSO

perl(1).

=cut


