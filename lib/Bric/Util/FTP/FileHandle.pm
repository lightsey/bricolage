package Bric::Util::FTP::FileHandle;

=pod

=head1 NAME

Bric::Util::FTP::FileHandle - Virtual FTP Server FileHandle

=head1 VERSION

$LastChangedRevision$

=cut

INIT {
    require Bric; our $VERSION = Bric->VERSION
}

=pod

=head1 DATE

$LastChangedDate$

=head1 DESCRIPTION

This module provides a file handle object for use by
Bric::Util::FTP::Server.

=head1 INTERFACE

This module inherits from Net::FTPServer::FileHandle and overrides the
required methods.  This class is used internally by Bric::Util::FTP::Server.

=cut

################################################################################
# Dependencies
################################################################################
# Standard Dependencies
use strict;

################################################################################
# Programmatic Dependences
use Bric::Config qw(:ftp);
use Bric::Util::DBI qw(:all);
use Bric::Util::Time qw(:all);
use Bric::App::Authz qw(:all);
use Bric::Util::Burner;
use Bric::Biz::Asset::Formatting;
use Bric::Util::Priv::Parts::Const qw(:all);
use Bric::Util::FTP::DirHandle;
use Net::FTPServer::FileHandle;
use IO::Scalar;
use Bric::Util::Event;

################################################################################
# Inheritance
################################################################################
our @ISA = qw(Net::FTPServer::FileHandle);

=head2 Constructors

=over 4

=cut

=item new($ftps, $template, $site_id, $oc_id, $category_id)

Creates a new Bric::Util::FTP::FileHandle object. Requires three arguments:
the Bric::Util::FTP::Server object, the Bric::Biz::Asset::Formatting object
that this filehandle represents (aka the template object), and the category_id
for the category that thetemplate is in.

=cut

sub new {
  my $class       = shift;
  my $ftps        = shift;
  my $template    = shift;
  my $site_id     = shift;
  my $oc_id       = shift;
  my $category_id = shift;
  my $deploy      = shift;

  my $filename =  $template->get_file_name;
  $filename = substr($filename, rindex($filename, '/') + 1);

  # Create object.
  my $self = Net::FTPServer::FileHandle->new($ftps, $filename);

  $self->{template}    = $template;
  $self->{category_id} = $category_id;
  $self->{oc_id}       = $oc_id;
  $self->{site_id}     = $site_id;
  $self->{filename}    = $filename;
  $self->{deploy}     = $deploy || FTP_DEPLOY_ON_UPLOAD;

  print STDERR __PACKAGE__, "::new() : ", $template->get_file_name, "\n"
    if FTP_DEBUG;

  return bless $self, $class;
}

=back

=head2 Public Instance Methods

=over 4

=item open($mode)

This method opens this template object for access using the provided
mode ('r', 'w' or 'a').  The method returns an IO::Scalar object that
will be used by Net::FTPServer to access the template text.  For
read-only access a plain IO::Scalar object is returned.  For
write-methods an internal tied class -
Bric::Util::FTP::FileHandle::SCALAR - is used with IO::Scalar to
provide write-access to the data in the database.  Returns undef on
failure.

=cut

# Open the file handle.
sub open {
  my $self = shift;
  my $mode = shift;
  my $template = $self->{template};

  print STDERR __PACKAGE__, "::open('$mode') : ", $template->get_file_name, "\n"
    if FTP_DEBUG;

  if ($mode eq "r") {
    # check write access
    return undef unless $self->can_read;

    # reads are easy - just return an IO::Scalar with the template data
    my $data = $template->get_data;
    return new IO::Scalar \$data;
  } elsif ($mode eq "w" or $mode eq "a") {
    # check write access
    return undef unless $self->can_write;

    # first clear the data unless appending
    $template->set_data('')
      unless $mode eq 'a';

    # create a tied scalar and return an IO::Scalar attached to it
    my $data;
    tie $data, 'Bric::Util::FTP::FileHandle::SCALAR',
	$template, $self->{ftps}{user_obj}, @{$self}{qw(ftps deploy)};
    my $handle = new IO::Scalar \$data;

    # seek if appending
    $handle->seek(length($template->get_data))
      if $mode eq 'a';

    return $handle;
  }
}

=item dir()

Returns the directory handle for the category that this template is
in.  Calls Bric::Util::FTP::DirHandle->new().

=cut

sub dir {
  my $self = shift;
  print STDERR __PACKAGE__, "::dir() : ", $self->{template}->get_file_name, "\n"
    if FTP_DEBUG;
  return Bric::Util::FTP::DirHandle->new($self->{ftps},
                                         $self->dirname,
                                         $self->{site_id},
                                         $self->{oc_id},
                                         $self->{category_id});
}

=item status()

This method returns information about the object.  The return value is
a list with seven elements - ($mode, $perms, $nlink, $user, $group,
$size, $time).  To quote the good book (Net::FTPServer::Handle):

          $mode     Mode        'd' = directory,
                                'f' = file,
                                and others as with
                                the find(1) -type option.
          $perms    Permissions Permissions in normal octal numeric format.
          $nlink    Link count
          $user     Username    In printable format.
          $group    Group name  In printable format.
          $size     Size        File size in bytes.
          $time     Time        Time (usually mtime) in Unix time_t format.

$mode is always 'f'.  $perms is set depending on wether the template
is checked out and whether the user has access to edit the template.
$nlink is always 1.  $user is set to the user that has the template
checked out or "nobody" for checked in templates.  $group is "co" if
the template is checked out, "ci" if it's checked in.  $size is the
size of the template text in bytes.  $time is set to the deploy_time()
of the template.

=cut

sub status {
  my $self = shift;
  my $template = $self->{template};

  print STDERR __PACKAGE__, "::status() : ", $template->get_file_name, "\n"
    if FTP_DEBUG;

  my $data = $template->get_data || "";
  my $size = length($data);
  my $date = $template->get_deploy_date('epoch') || 0;

  my $owner = $template->get_user__id;
  if (defined $owner) {

    # if checked out, get the username return read-only
    my $login = 'nobody';
    my $mode = 0444;
    if (my $user = Bric::Biz::Person::User->lookup({id => $owner})) {
        $login = $user->get_login;
        $mode = 0777 if $user->get_id == $self->{ftps}{user_obj}->get_id;
    }

    return ( 'f', $mode, 1, $login, "co", $size,  $date);

  } else {
    # otherwise check for write privs - can't use chk_authz because it
    # works with the web login caching system.
    my $priv = $self->{ftps}{user_obj}->what_can($template);
    my $mode;
    my $twid = $template->get_workflow_id;
    if (!$priv or $priv == DENY) {
        # They can't touch it.
        $mode = 0000;
    } elsif ($priv >= RECALL) {
        # They have full access.
        $mode = 0777;
    } elsif ($twid and my $d = $template->get_current_desk) {
        # See if they have access to the desk.
        if (chk_authz(undef, READ, $d->get_asset_grp, $d->get_grp_ids)
            && $priv >= EDIT) {
            # They have full access.
            $mode = 0777;
        } else {
            # They can read it.
            $mode = 0444;
        }
    } else {
        # They can read it.
        $mode = 0444;
    }
    return ( 'f', $mode, 1, "nobody", "ci", $size,  $date);
  }
}

=item move()

Deploys the template if the new name is the same as the template name followed by
'.deploy'. Otherwise it's a no-op.

=cut
sub move {
  my $self = shift;
  my $dirh = shift;
  my $filename  = shift;
  my $template = $self->{template};
  return 0 unless $filename =~ /\.deploy$/;
  print STDERR __PACKAGE__, "\n\n::move(", $template->get_file_name,
    ",$filename)\n"
    if FTP_DEBUG;

    $self->{deploy} = 1;
    # create a tied scalar and return an IO::Scalar attached to it
    my $data;
    tie $data, 'Bric::Util::FTP::FileHandle::SCALAR',
	$template, $self->{ftps}{user_obj}, @{$self}{qw(ftps deploy)};

    $data = $template->get_data;
#    my $handle = new IO::Scalar \$data;
#    print $handle $template->get_data;
    return 1;
}

=item delete()

Deletes the current template.  This has the same effect as deleting
the template through the UI - it undeploys the template if it's
deployed and marks it inactive.

=cut

sub delete {
  my $self = shift;
  my $template = $self->{template};

  print STDERR __PACKAGE__, "::delete() : ", $template->get_file_name, "\n"
    if FTP_DEBUG;

  # delete code equivalent to delete callback in
  # comp/widgets/tmpl_prof

  # remove from current desk
  my $desk = $template->get_current_desk;
  if ($desk) {
      $desk->checkin($template);
      $desk->remove_asset($template);
      $desk->save;
  }

  # log the removal
  Bric::Util::Event->new({ key_name  => 'formatting_rem_workflow',
                           obj       => $template,
                           user      => $self->{ftps}{user_obj},
                         });

  # undeploy and deactivate
  my $burn = Bric::Util::Burner->new;
  $burn->undeploy($template);
  $template->deactivate;
  $template->save;

  # log the deactivation
  Bric::Util::Event->new({ key_name  => 'formatting_deact',
                           obj       => $template,
                           user      => $self->{ftps}{user_obj},
                         });

  return 1;
}

=item can_*()

Returns permissions information for various activites.  can_read()
always returns 1 since templates can always be read.  can_rename() and
can_delete() return 0 since these operations are not yet supported.
can_write() and can_append() return 1 if the user can write to the
template - if it's checked in and the user has permission.

=cut

# fixed properties
sub can_read   {  1; }
sub can_rename {  1; }
sub can_delete {  1; }

# check to see if template is checked out
sub can_write  {
  my $self = shift;
  my @stats = $self->status();

  # this should probably be a real bit test for u+w
  if ($stats[1] == 0777) {
    return 1;
  } else {
    return 0;
  }
}

*can_append = \&can_write;

=back

=head1 PRIVATE

=head2 Private Classes

=over 4

=item Bric::Util::FTP::FileHandle::SCALAR

This class provides a tied scalar interface to a template object's
data.  The TIESCALAR constructor takes a template object as a single
argument.  Writes to the tied scalar result in the template object
being altered, saved, checked-in and deployed.

=back

=cut

package Bric::Util::FTP::FileHandle::SCALAR;
use strict;
use warnings;

use Bric::Config qw(FTP_DEBUG);
use Bric::Util::Time qw(:all);
use Bric::Util::Event;
use Bric::Util::Priv::Parts::Const qw(:all);

sub TIESCALAR {
  my $pkg = shift;
  my $template = shift;
  my $user = shift;
  my $ftps = shift;
  my $deploy = shift;
  my $self = { template => $template,
               user     => $user,
               ftps     => $ftps,
               deploy   => $deploy };

  print STDERR __PACKAGE__, "::TIESCALAR()\n" if FTP_DEBUG;
  return bless $self, $pkg;
}

sub FETCH {
  my $self = shift;
  print STDERR __PACKAGE__, "::FETCH()\n" if FTP_DEBUG;
  return $self->{template}->get_data();
}

# This method can only be called if the mode is "w" (writeable).
sub STORE {
    my $self = shift;
    my $data = shift;
    my $template = $self->{template};
    my $user = $self->{user};
    print STDERR __PACKAGE__, "::STORE()\n" if FTP_DEBUG;

    # Put the template into workflow.
    if (not $template->get_workflow_id) {
        # Recall it into workflow.
        $self->{ftps}->move_into_workflow($template)
    } elsif (not $template->get_desk_id) {
        # Move it to the start desk and check it out.
        $self->{ftps}->move_onto_desk($template)
    }

    # save the new code
    $template->set_data($data);
    $template->save;

    # log the save
    Bric::Util::Event->new({ key_name  => 'formatting_save',
                             obj       => $template,
                             user      => $user,
                         });

    if ($self->{deploy}) {
        # checkin the template
        $template->checkin;

        # remove from desk
        my $cur_desk = $template->get_current_desk;
        unless ($cur_desk && $cur_desk->can_publish) {
            # Find a desk to deploy from.
            my $wf = Bric::Biz::Workflow->lookup({
                id => $template->get_workflow_id
            });
            my $pub_desk;
            foreach my $d ($wf->allowed_desks) {
                $pub_desk = $d and last if $d->can_publish
                  && $self->{ftps}{user_obj}->can_do($d, READ);
            }

            # Transfer the template to the publish desk.
            if ($cur_desk) {
                $cur_desk->transfer({ to    => $pub_desk,
                                      asset => $template });
                $cur_desk->save;
            } else {
                $pub_desk->accept({ asset => $template });
            }

            # Save the deploy desk and log it.
            $pub_desk->save;
            Bric::Util::Event->new({ key_name  => "formatting_moved",
                                     obj       => $template,
                                     user      => $user,
                                     attr      => { Desk => $pub_desk->get_name },
                                 });
        }

        # Make sure they have permission to deploy (publish).
        unless ($self->{ftps}{user_obj}->can_do($template, PUBLISH)) {
            warn "Cannot publish ", $template->get_name,
              ": permission denied\n";
            return;
        }

        # Now remove it!
        $cur_desk->remove_asset($template);
        $cur_desk->save;

        # clear the workflow ID
        if ($template->get_workflow_id) {
            $template->set_workflow_id(undef);
              Bric::Util::Event->new({ key_name  => "formatting_rem_workflow",
                                       obj       => $template,
                                       user      => $user,
                                   });
        }

        $template->save;
        # get a new burner
        my $burner = Bric::Util::Burner->new;

        # deploy and save
        $burner->deploy($template);
        $template->set_deploy_date(strfdate());
        $template->set_deploy_status(1);
        $template->set_published_version($template->get_current_version);
        $template->save;

        # Be sure to undeploy it from the user's sandbox.
        my $sb = Bric::Util::Burner->new({user_id => $user->get_id });
        $sb->undeploy($template);

        # log the deploy
        Bric::Util::Event->new({ key_name  => $template->get_deploy_status
                                              ? 'formatting_redeploy'
                                              : 'formatting_deploy',
                                 obj       => $template,
                                 user      => $user,
                             });
    } else {
        # Simply deploy it to the user's sandbox.
        my $burner = Bric::Util::Burner->new({user_id => $user->get_id });
        $burner->deploy($template);
    }
  return $data;
}

1;

__END__

=pod

=head1 AUTHOR

Sam Tregar (stregar@about-inc.com)

=head1 SEE ALSO

Net:FTPServer::FileHandle

L<Bric::Util::FTP::Server>

L<Bric::Util::FTP::DirHandle>

=cut
