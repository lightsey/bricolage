<%doc>
###############################################################################

=head1 NAME

widgets/help/help.mc

=head1 SYNOPSIS

  <& "/widgets/help/help.mc" &>

=head1 DESCRIPTION

Returns a help button with a link to a helpfile based on $r->uri().

=head1 AUTHOR

Sam Tregar <stregar@about-inc.com>

=cut

</%doc>
<%once>;
my $widget = 'help';
</%once>
<%perl>
  set_state_data($widget, \%ARGS);
#  my $DEBUG = 1;
  my $uri = $r->uri;

#  print STDERR "HELP : real uri : $uri\n" if $DEBUG;

  # no trailing slash
  $uri =~ s!/$!!;

  # slice off trailing numbers
  $uri =~ s!\d+/?!!g;

  # really no trailing slash
  $uri =~ s!/$!!;

  # top-level is /workflow/profile/workspace
  $uri = '/workflow/profile/workspace' unless length $uri;

  # add on help and .html
  $uri = "/help/$lang_key" . $uri;
  $uri .= '.html' unless $uri =~ /\.html$/;

#  print STDERR "HELP : help uri : $uri\n" if $DEBUG;
</%perl><a href="#" title="Help" onclick="window.open('<% $uri %>', 'Help_<% SERVER_WINDOW_NAME %>', 'menubar=0,location=0,toolbar=0,personalbar=0,status=0,scrollbars=1,height=600,width=505');return false;"><img src="/media/images/<% $lang_key %>/help.gif" alt="Help" /></a>