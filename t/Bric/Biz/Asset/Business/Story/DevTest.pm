package Bric::Biz::Asset::Business::Story::DevTest;
use strict;
use warnings;
use base qw(Bric::Test::DevBase);
use Test::More;
use Test::Exception;
use Bric::Util::DBI qw(:standard);
use Bric::Biz::ATType;
use Bric::Biz::AssetType;
use Bric::Biz::Asset::Business::Story;
use Bric::Biz::Workflow::Parts::Desk;
use Bric::Biz::Workflow;
use Bric::Biz::Category;
use Bric::Util::Grp::Desk;
use Bric::Util::Grp::Story;
use Bric::Util::Grp::Workflow;
use Bric::Util::Grp::CategorySet;

sub class { 'Bric::Biz::Asset::Business::Story' }
sub table { 'story' }

my $CATEGORY = Bric::Biz::Category->lookup({ id => 1 });

# this will be filled during setup
my $OBJ_IDS = {};
my $OBJ = {};
my @CATEGORY_GRP_IDS;
my @WORKFLOW_GRP_IDS;
my @DESK_GRP_IDS;
my @STORY_GRP_IDS;
my @ALL_DESK_GRP_IDS;
my @REQ_DESK_GRP_IDS;
my @EXP_GRP_IDS;

##############################################################################
# The element object we'll use throughout.
my $elem;
sub get_elem {
    ($elem) = Bric::Biz::AssetType->list({ name => 'Story' });
    return $elem;
}

##############################################################################
# Arguments to the new() constructor. Used by construct(). Override as
# necessary in subclasses.
sub new_args {
    my $self = shift;
    ( element       => $self->get_elem,
      user__id      => $self->user_id,
      source__id    => 1,
      primary_oc_id => 1,
      description   => 'foo',
      site_id       => 100,
    )
}

##############################################################################
# Constructs a new object.
sub construct {
    my $self = shift;
    my $story = $self->class->new({ $self->new_args, @_ });
    $story->add_categories( [ $CATEGORY ] );
    $story->set_primary_category($CATEGORY);
    $story->save;
    $self->add_del_ids($story->get_id);
    return $story;
}

##############################################################################
# Test the clone() method.
##############################################################################

sub test_clone : Test(15) {

    my $self = shift;
    ok( my $story = Bric::Biz::Asset::Business::Story->new(
      { element       => $self->get_elem,
        user__id      => $self->user_id,
        name          => 'Victor', 
        slug          => 'hugo',
        source__id    => 1,
        site_id       => 100,
      }), "Construct story" );

    $story->add_categories( [ $CATEGORY ] );
    $story->set_primary_category($CATEGORY);

    ok( $story->save, "Save story" );

    # Save the ID for cleanup.
    ok( my $sid = $story->get_id, "Get ID" );
    my $key = $self->class->key_name;
    $self->add_del_ids([$sid], $key);

    # Clone the story.
    ok( $story->clone, "Clone story" );
    ok( $story->save, "Save cloned story" );
    ok( my $cid = $story->get_id, "Get cloned ID" );
    $self->add_del_ids([$cid], $key);

    # Lookup the original story.
    ok( my $orig = $self->class->lookup({ id => $sid }),
        "Lookup original story" );

    # Lookup the cloned story.
    ok( my $clone = $self->class->lookup({ id => $cid }),
        "Lookup cloned story" );

    # Check that the story is really cloned!
    isnt( $sid, $cid, "Check for different IDs" );
    is( $orig->get_title, $clone->get_title, "Compare titles" );
    is( $orig->get_slug, $clone->get_slug, "Compare slugs" );
    is( $orig->get_uri, $clone->get_uri, "Compare uris" );

    # Check that the output channels are the same.
    ok( my @oocs = $orig->get_output_channels, "Get original OCs" );
    ok( my @cocs = $clone->get_output_channels, "Get cloned OCs" );
    is_deeply(\@oocs, \@cocs, "Compare OCs" );
}

##############################################################################
# Test the SELECT methods
##############################################################################

sub test_select_methods: Test(44) {
    my $self = shift;

    # let's grab existing 'All' group info
    my $all_workflow_grp_id = Bric::Util::Grp->lookup({ name => 'All Workflows' })->get_id();
    my $all_cats_grp_id = Bric::Util::Grp->lookup({ name => 'All Categories' })->get_id();
    my $all_desks_grp_id = Bric::Util::Grp->lookup({ name => 'All Desks' })->get_id();
    my $all_stories_grp_id = Bric::Util::Grp->lookup({ name => 'All Stories' })->get_id();

    # now we'll create some test objects
    my ($i);
    for ($i = 0; $i < 5; $i++) {
        my $time = time;
        my ($cat, $desk, $workflow, $story, $grp);
        # create categories
        $cat = Bric::Biz::Category->new({ site_id => 100,
                                          name => "_test_$time.$i", 
                                          description => '',
                                          directory => "_test_$time.$i",
                                       });
        $CATEGORY->add_child([$cat]);
        $cat->save();
        push @{$OBJ_IDS->{category}}, $cat->get_id();
        push @{$OBJ->{category}}, $cat;
        # create some category groups
        $grp = Bric::Util::Grp::CategorySet->new({ name => "_test_$time.$i",
                                                   description => '',
                                                   obj => $cat });

        $grp->add_member({obj => $cat });
        # save the group ids
        $grp->save();
        push @{$OBJ_IDS->{grp}}, $grp->get_id();
        push @CATEGORY_GRP_IDS, $grp->get_id();

        # create desks 
        $desk = Bric::Biz::Workflow::Parts::Desk->new({ 
                                        name => "_test_$time.$i", 
                                        description => '',
                                     });
        $desk->save();
        push @{$OBJ_IDS->{desk}}, $desk->get_id();
        push @{$OBJ->{desk}}, $desk;
        # create some desk groups
        $grp = Bric::Util::Grp::Desk->new({ name => "_test_$time.$i",
                                            description => '',
                                            obj => $desk,
                                         });
        # save the group ids
        $grp->add_member({ obj => $desk });
        $grp->save();
        push @{$OBJ_IDS->{grp}}, $grp->get_id();
        push @DESK_GRP_IDS, $grp->get_id();

        # create workflows
        $workflow = Bric::Biz::Workflow->new({ 
                                        type => Bric::Biz::Workflow::STORY_WORKFLOW,
                                        name => "_test_$time.$i",
                                        start_desk => $desk,
                                        description => 'test',
                                        site_id => 100, #Use default site_id
                                     });
        $workflow->save();
        push @ALL_DESK_GRP_IDS, $workflow->get_all_desk_grp_id;
        push @REQ_DESK_GRP_IDS, $workflow->get_req_desk_grp_id;
        push @{$OBJ_IDS->{workflow}}, $workflow->get_id();
        push @{$OBJ->{workflow}}, $workflow;
        # create some workflow groups
        $grp = Bric::Util::Grp::Workflow->new({ name => "_test_$time.$i",
                                                description => '',
                                                obj => $workflow,
                                             });
        # save the group ids
        $grp->add_member({ obj => $workflow });
        $grp->save();
        push @{$OBJ_IDS->{grp}}, $grp->get_id();
        push @WORKFLOW_GRP_IDS, $grp->get_id();
        
        # create some story groups
        $grp = Bric::Util::Grp::Story->new({ name => "_GRP_test_$time.$i" });
        # save the group ids
        $grp->save();
        push @{$OBJ_IDS->{grp}}, $grp->get_id();
        push @{$OBJ->{story_grp}}, $grp;
        push @STORY_GRP_IDS, $grp->get_id();
    }

    # set up to do the deletes
    foreach my $table (qw(grp category workflow desk)) {
        $self->add_del_ids( $OBJ_IDS->{$table}, $table );
    }

    # look up a story element
    my ($element) = Bric::Biz::AssetType->list({ name => 'Story' });

    # and a user
    my $admin_id = $self->user_id();

    # create some stories
    my (@story,$time, $got, $expected);

    # A story with one category (admin user)
    $time = time;
    $story[0] = Bric::Biz::Asset::Business::Story->new({
                                                       name        => "_test_$time",
                                                       description => 'this is a test',
                                                       priority    => 1,
                                                       source__id  => 1,
                                                       slug        => 'test',
                                                       user__id    => $admin_id,
                                                       element     => $element, 
                                                       site_id     => 100,
                                                   });
    $story[0]->add_categories([ $OBJ->{category}->[0] ]);
    $story[0]->set_primary_category($OBJ->{category}->[0]);
    $story[0]->checkin();
    $story[0]->save();
    push @{$OBJ_IDS->{story}}, $story[0]->get_id();
    $self->add_del_ids( $story[0]->get_id() );

    # Try doing a lookup 
    $expected = $story[0];
    ok( $got = class->lookup({ id => $OBJ_IDS->{story}->[0] }), 'can we call lookup on a Story' );
    is( $got->get_name(), $expected->get_name(), '... does it have the right name');
    is( $got->get_description(), $expected->get_description(), '... does it have the right desc');

    # check the URI
    my $exp_uri = $OBJ->{category}->[0]->get_uri . '/test';
    like( $got->get_primary_uri(), qr/^$exp_uri/, '...does the uri match the category and slug');

    # check the grp IDs
    my $exp_grp_ids = [ $all_cats_grp_id, 
                        $all_stories_grp_id, 
                        $OBJ_IDS->{grp}->[0] ];
    push @EXP_GRP_IDS, $exp_grp_ids;
    my $got_grp_ids = $got->get_grp_ids();
    eq_set( $got_grp_ids , $exp_grp_ids, '... does it have the right grp_ids' );

    # ... with multiple cats
    $time = time;
    $story[1] = Bric::Biz::Asset::Business::Story->new({
                                                       name        => "_test_$time",
                                                       description => 'this is a test',
                                                       priority    => 1,
                                                       source__id  => 1,
                                                       slug        => 'test',
                                                       user__id    => $admin_id,
                                                       element     => $element, 
                                                       site_id     => 100,
                                                   });
    $story[1]->add_categories( $OBJ->{category} );
    $story[1]->set_primary_category( $OBJ->{category}->[1] );
    $story[1]->checkin();
    $story[1]->save();
    push @{$OBJ_IDS->{story}}, $story[1]->get_id();
    $self->add_del_ids( $story[1]->get_id());

    # Try doing a lookup 
    $expected = $story[1];
    ok( $got = class->lookup({ id => $OBJ_IDS->{story}->[1] }), 'can we call lookup on a Story with multiple categories' );
    is( $got->get_name(), $expected->get_name(), '... does it have the right name');
    is( $got->get_description(), $expected->get_description(), '... does it have the right desc');

    # check the URI
    $exp_uri = $OBJ->{category}->[1]->get_uri . '/test';
    like( $got->get_primary_uri(), qr/^$exp_uri/, '...does the uri match the category and slug');

    # check the grp IDs
    $exp_grp_ids = [ $all_cats_grp_id, 
                     $all_stories_grp_id, 
                     $CATEGORY_GRP_IDS[0],
                     $OBJ_IDS->{grp}->[4], 
                     $OBJ_IDS->{grp}->[8], 
                     $OBJ_IDS->{grp}->[12], 
                     $OBJ_IDS->{grp}->[16], 
                   ];
    push @EXP_GRP_IDS, $exp_grp_ids;
    $got_grp_ids = $got->get_grp_ids();
    eq_set( $got_grp_ids , $exp_grp_ids, '... does it have the right grp_ids' );

    # ... as a grp member
    $time = time;
    $story[2] = Bric::Biz::Asset::Business::Story->new({
                                                       name        => "_test_$time",
                                                       description => 'this is a test',
                                                       priority    => 1,
                                                       source__id  => 1,
                                                       slug        => 'test',
                                                       user__id    => $admin_id,
                                                       element     => $element, 
                                                       site_id     => 100,
                                                   });
    $story[2]->add_categories([ $OBJ->{category}->[0] ]);
    $story[2]->set_primary_category( $OBJ->{category}->[0] );
    $story[2]->checkin();
    $story[2]->save();
    push @{$OBJ_IDS->{story}}, $story[2]->get_id();
    $self->add_del_ids( $story[2]->get_id() );

    $OBJ->{story_grp}->[0]->add_member({ obj => $story[2] });
    $OBJ->{story_grp}->[0]->save();

    $expected = $story[2];
    ok( $got = class->lookup({ id => $OBJ_IDS->{story}->[2] }), 'can we call lookup on a Story which is itself in a grp' );
    is( $got->get_name(), $expected->get_name(), '... does it have the right name');
    is( $got->get_description(), $expected->get_description(), '... does it have the right desc');

    # check the URI
    $exp_uri = $OBJ->{category}->[0]->get_uri . '/test';
    like( $got->get_primary_uri(), qr/^$exp_uri/, '...does the uri match the category and slug');

    # check the grp IDs
    $exp_grp_ids = [ $all_cats_grp_id, 
                     $all_stories_grp_id,
                     $CATEGORY_GRP_IDS[0],
                     $STORY_GRP_IDS[0],
                   ];
    push @EXP_GRP_IDS, $exp_grp_ids;
    $got_grp_ids = $got->get_grp_ids();
    eq_set( $got_grp_ids , $exp_grp_ids, '... does it have the right grp_ids' );

    # ... a bunch of grps
    $time = time;
    $story[3] = Bric::Biz::Asset::Business::Story->new({
                                                       name        => "_test_$time",
                                                       description => 'this is a test',
                                                       priority    => 1,
                                                       source__id  => 1,
                                                       slug        => 'test',
                                                       user__id    => $admin_id,
                                                       element     => $element, 
                                                       site_id     => 100,
                                                   });
    $story[3]->add_categories([ $OBJ->{category}->[0] ]);
    $story[3]->set_primary_category( $OBJ->{category}->[0] );
    $story[3]->checkin();
    $story[3]->save();
    push @{$OBJ_IDS->{story}}, $story[3]->get_id();
    $self->add_del_ids( $story[3]->get_id() );

    $OBJ->{story_grp}->[0]->add_member({ obj => $story[3] });
    $OBJ->{story_grp}->[0]->save();

    $OBJ->{story_grp}->[1]->add_member({ obj => $story[3] });
    $OBJ->{story_grp}->[1]->save();

    $OBJ->{story_grp}->[2]->add_member({ obj => $story[3] });
    $OBJ->{story_grp}->[2]->save();

    $OBJ->{story_grp}->[3]->add_member({ obj => $story[3] });
    $OBJ->{story_grp}->[3]->save();

    $OBJ->{story_grp}->[4]->add_member({ obj => $story[3] });
    $OBJ->{story_grp}->[4]->save();

    $expected = $story[3];
    ok( $got = class->lookup({ id => $OBJ_IDS->{story}->[3] }), 'can we call lookup on a Story which is itself in a grp' );
    is( $got->get_name(), $expected->get_name(), '... does it have the right name');
    is( $got->get_description(), $expected->get_description(), '... does it have the right desc');

    # check the URI
    $exp_uri = $OBJ->{category}->[0]->get_uri . '/test';
    like( $got->get_primary_uri(), qr/^$exp_uri/, '...does the uri match the category and slug');

    # check the grp IDs
    $exp_grp_ids = [ $all_cats_grp_id, 
                     $all_stories_grp_id,
                     $CATEGORY_GRP_IDS[0],
                     $STORY_GRP_IDS[0],
                     $STORY_GRP_IDS[1],
                     $STORY_GRP_IDS[2],
                     $STORY_GRP_IDS[3],
                     $STORY_GRP_IDS[4],
                   ];
    push @EXP_GRP_IDS, $exp_grp_ids;
    $got_grp_ids = $got->get_grp_ids();
    eq_set( $got_grp_ids , $exp_grp_ids, '... does it have the right grp_ids' );

    # ... now try a workflow
    $time = time;
    $story[4] = Bric::Biz::Asset::Business::Story->new({
                                                       name        => "_test_$time",
                                                       description => 'this is a test',
                                                       priority    => 1,
                                                       source__id  => 1,
                                                       slug        => 'test',
                                                       user__id    => $admin_id,
                                                       element     => $element, 
                                                       site_id     => 100,
                                                   });
    $story[4]->add_categories([ $OBJ->{category}->[0] ]);
    $story[4]->set_primary_category($OBJ->{category}->[0]);
    $story[4]->set_workflow_id( $OBJ->{workflow}->[0]->get_id() );
    $story[4]->checkin();
    $story[4]->save();
    push @{$OBJ_IDS->{story}}, $story[4]->get_id();
    $self->add_del_ids( $story[4]->get_id() );

    # add it to the workflow

    # Try doing a lookup 
    $expected = $story[4];
    ok( $got = class->lookup({ id => $OBJ_IDS->{story}->[4] }), 'can we call lookup on a Story' );
    is( $got->get_name(), $expected->get_name(), '... does it have the right name');
    is( $got->get_description(), $expected->get_description(), '... does it have the right desc');

    # check the URI
    $exp_uri = $OBJ->{category}->[0]->get_uri . '/test';
    like( $got->get_primary_uri(), qr/^$exp_uri/, '...does the uri match the category and slug');

    # check the grp IDs
    $exp_grp_ids = [ 
                        $all_workflow_grp_id,
                        $all_cats_grp_id, 
                        $all_stories_grp_id, 
                        $CATEGORY_GRP_IDS[0],
                        $WORKFLOW_GRP_IDS[0],
                    ];
    push @EXP_GRP_IDS, $exp_grp_ids;
    $got_grp_ids = $got->get_grp_ids();
    eq_set( $got_grp_ids , $exp_grp_ids, '... does it have the right grp_ids' );

    # ... desk
    $time = time;
    $story[5] = Bric::Biz::Asset::Business::Story->new({
                                                       name        => "_test_$time",
                                                       description => 'this is a test',
                                                       priority    => 1,
                                                       source__id  => 1,
                                                       slug        => 'test',
                                                       user__id    => $admin_id,
                                                       element     => $element, 
                                                       site_id     => 100,
                                                   });
    $story[5]->add_categories([ $OBJ->{category}->[0] ]);
    $story[5]->set_primary_category($OBJ->{category}->[0]);
    $story[5]->set_workflow_id( $OBJ->{workflow}->[0]->get_id() );
    $story[5]->set_current_desk( $OBJ->{desk}->[0] );
    $story[5]->checkin();
    $story[5]->save();
    push @{$OBJ_IDS->{story}}, $story[5]->get_id();
    $self->add_del_ids( $story[5]->get_id() );

    # add it to the workflow

    # Try doing a lookup 
    $expected = $story[5];
    ok( $got = class->lookup({ id => $OBJ_IDS->{story}->[5] }), 'can we call lookup on a Story' );
    is( $got->get_name(), $expected->get_name(), '... does it have the right name');
    is( $got->get_description(), $expected->get_description(), '... does it have the right desc');

    # check the URI
    $exp_uri = $OBJ->{category}->[0]->get_uri . '/test';
    like( $got->get_primary_uri(), qr/^$exp_uri/, '...does the uri match the category and slug');

    # check the grp IDs
    $exp_grp_ids = [ 
                        $all_workflow_grp_id,
                        $all_cats_grp_id, 
                        $all_stories_grp_id, 
                        $all_desks_grp_id, 
                        $CATEGORY_GRP_IDS[0],
                        $DESK_GRP_IDS[0],
                        $ALL_DESK_GRP_IDS[0],
                        $REQ_DESK_GRP_IDS[0],
                        $WORKFLOW_GRP_IDS[0],
                    ];
    push @EXP_GRP_IDS, $exp_grp_ids;
    $got_grp_ids = $got->get_grp_ids();
    eq_set( $got_grp_ids , $exp_grp_ids, '... does it have the right grp_ids' );

    # try listing something up by at least key in each table
    # be sure to try to get them both as a ref and a list
    my @got_ids;
    my @got_grp_ids;

    ok( my @got = class->list({ name => '_test%'}), 'lets do a search by name' );
    ok( $got = class->list({ name => '_test%', Order => 'name' }), 'lets do a search by name' );
    # check the ids
    foreach (@$got) {
        push @got_ids, $_->get_id();
        push @got_grp_ids, \@{$_->get_grp_ids()};
    }
    eq_set( \@got_ids, $OBJ_IDS->{story}, '... did we get the right list of ids out' );
    eq_set( \@got_grp_ids, \@EXP_GRP_IDS, '... and did we get the right grp_ids' );
    undef @got_ids;
    undef @got_grp_ids;

    ok( $got = class->list({ title => '_test%', Order => 'name' }), 'lets do a search by title' );
    # check the ids
    foreach (@$got) {
        push @got_ids, $_->get_id();
        push @got_grp_ids, \@{$_->get_grp_ids()};
    }
    eq_set( \@got_ids, $OBJ_IDS->{story}, '... did we get the right list of ids out' );
    eq_set( \@got_grp_ids, \@EXP_GRP_IDS, '... and did we get the right grp_ids' );
    undef @got_ids;
    undef @got_grp_ids;

    ok( $got = class->list({ primary_uri => '/_test%', Order => 'title' }), 
      'lets do a search by primary uri' );
    # check the ids
    foreach (@$got) {
        push @got_ids, $_->get_id();
        push @got_grp_ids, \@{$_->get_grp_ids()};
    }
    eq_set( \@got_ids, $OBJ_IDS->{story}, '... did we get the right list of ids out' );
    eq_set( \@got_grp_ids, \@EXP_GRP_IDS, '... and did we get the right grp_ids' );
    undef @got_ids;
    undef @got_grp_ids;

    ok( $got = class->list({ category_id => $OBJ_IDS->{category}->[0], Order => 'title' }), 
      'lets do a search by category_id' );
    # check the ids
    foreach (@$got) {
        push @got_ids, $_->get_id();
        push @got_grp_ids, \@{$_->get_grp_ids()};
    }
    eq_set( \@got_ids, $OBJ_IDS->{story}, '... did we get the right list of ids out' );
    eq_set( \@got_grp_ids, \@EXP_GRP_IDS, '... and did we get the right grp_ids' );
    undef @got_ids;
    undef @got_grp_ids;

    # finally do this by grp_ids
    ok( $got = class->list({ grp_id => $OBJ->{story_grp}->[0]->get_id(), Order => 'name' }), 
      'getting by grp_id' );
    my $number = @$got;
    is( $number, 2, 'there should be two stories in the first grp' );
    is( $got->[0]->get_id(), $story[2]->get_id(), '... and they should be numbers 2' );
    is( $got->[1]->get_id(), $story[3]->get_id(), '... and 3' );

    # try listing IDs, again at least one key per table
    ok( $got = class->list_ids({ name => '_test%', Order => 'name' }), 
      'lets do an IDs search by name' );
    # check the ids
    foreach (@$got) {
        push @got_ids, $_;
    }
    eq_set( \@got_ids, $OBJ_IDS->{story}, '... did we get the right list of ids out' );
    undef @got_ids;

    ok( $got = class->list_ids({ title => '_test%', Order => 'name' }), 'lets do an ids search by title' );
    # check the ids
    foreach (@$got) {
        push @got_ids, $_;
    }
    eq_set( \@got_ids, $OBJ_IDS->{story}, '... did we get the right list of ids out' );
    undef @got_ids;

    ok( $got = class->list_ids({ primary_uri => '/_test%', Order => 'name' }), 'lets do an ids search by primary uri' );
    # check the ids
    foreach (@$got) {
        push @got_ids, $_;
    }
    eq_set( \@got_ids, $OBJ_IDS->{story}, '... did we get the right list of ids out' );
    undef @got_ids;

    # finally do this by grp_ids
    ok( $got = class->list_ids({ grp_id => $OBJ->{story_grp}->[0]->get_id(), Order => 'title' }), 'getting by grp_id' );
    $number = @$got;
    is( $number, 2, 'there should be two stories in the first grp' );
    is( $got->[0], $story[2]->get_id(), '... and they should be numbers 2' );
    is( $got->[1], $story[3]->get_id(), '... and 3' );


    # now let's try a limit
    ok( $got = class->list({ Order => 'title', Limit => 3 }), 'try setting a limit of 3');
    is( @$got, 3, '... did we get exactly 3 stories back' );

    # test Offset
    ok( $got = class->list({ grp_id => $OBJ->{story_grp}->[0]->get_id(), Order => 'title', Offset => 1 }), 'try setting an offset of 2 for a search that just returned 3 objs');
    is( @$got, 1, '... Offset gives us #2 of 2' );
    
}

###############################################################################
## Test primary_oc_id property.
###############################################################################

sub test_primary_oc_id : Test(8) {
    my $self = shift;
    my $class = $self->class;
    ok( my $key = $class->key_name, "Get key" );
    return "OCs tested only by subclass" if $key eq 'biz';

    ok( my $ba = $self->construct( name => 'Flubberman',
                                   slug => 'hugoman'),
        "Construct asset" );
    $ba->add_categories([ $CATEGORY ]);
    $ba->set_primary_category($CATEGORY);
    ok( $ba->save, "Save asset" );

    # Save the ID for cleanup.
    ok( my $id = $ba->get_id, "Get ID" );
    $self->add_del_ids([$id], $key);

    is( $ba->get_primary_oc_id, 1, "Check primary OC ID" );

    # Try list().
    ok( my @bas = $class->list({ primary_oc_id => 1,
                                 user__id => $self->user_id }),
        "Get asset list" );
    is( scalar @bas, 1, "Check for one asset" );
    is( $bas[0]->get_primary_oc_id, 1, "Check for OC ID 1" );
}

##############################################################################
# Test output channel associations.
##############################################################################

sub test_oc : Test(35) {
    my $self = shift;
    my $class = $self->class;
    ok( my $key = $class->key_name, "Get key" );
     return "OCs tested only by subclass" if $key eq 'biz';
    ok( my $ba = $self->construct, "Construct $key object" );
    ok( my $elem = $self->get_elem, "Get element object" );

    # Make sure there are the same of OCs yet as in the element.
    ok( my @eocs = $elem->get_output_channels, "Get Element OCs" );
    ok( my @ocs = $ba->get_output_channels, "Get $key OCs" );
    #is( scalar @ocs, 1, "Check for 1 OC" );
    is( scalar @eocs, scalar @ocs, "Check for same number of OCs" );
    is( $eocs[0]->get_id, $ocs[0]->get_id, "Compare for same OC ID" );

    # have to add a category
    my $cat = Bric::Biz::Category->lookup({ id => 1 });
    $ba->add_categories([$cat]);
    $ba->set_primary_category($cat);

    # Save the asset object.
    ok( $ba->save, "Save ST" );
    ok( my $baid = $ba->get_id, "Get ST ID" );
    $self->add_del_ids($baid, $key);

    # Grab the element's first OC.
    ok( my $oc = $eocs[0], "Grab the first OC" );
    ok( my $ocname = $oc->get_name, "Get the OC's name" );

    # Try removing the OC.
    ok( $ba->del_output_channels($oc), "Delete OC from $key" );
    @ocs = $ba->get_output_channels;
    is( scalar @ocs, 0, "No more OCs" );

    # Add the new output channel to the asset.
    ok( $ba->add_output_channels($oc), "Add OC" );
    ok( @ocs = $ba->get_output_channels, "Get OCs" );
    is( scalar @ocs, 1, "Check for 1 OC" );
    is( $ocs[0]->get_name, $ocname, "Check OC name" );

    # Save it and verify again.
    ok( $ba->save, "Save ST" );
    ok( @ocs = $ba->get_output_channels, "Get OCs again" );
    is( scalar @ocs, 1, "Check for 1 OC again" );
    is( $ocs[0]->get_name, $ocname, "Check OC name again" );

    # Look up the asset in the database and check OCs again.
    ok( $ba = $class->lookup({ id => $baid }), "Lookup $key" );
    ok( @ocs = $ba->get_output_channels, "Get OCs 3" );
    is( scalar @ocs, 1, "Check for 1 OC 3" );
    is( $ocs[0]->get_name, $ocname, "Check OC name 3" );

    # Now check it in and make sure that the OCs are still properly associated
    # with the new version.
    ok( $ba->checkin, "Checkin asset" );
    ok( $ba->save, "Save new version" );
    ok( $ba->checkout({ user__id => $self->user_id }), "Checkout new version" );
    ok( $ba->save, "Save new version" );
    ok( my $version = $ba->get_version, "Get Version number" );
    ok( $ba = $class->lookup({ id => $baid }), "Lookup new version of $key" );
    is( $ba->get_version, $version, "Check version number" );
    ok( @ocs = $ba->get_output_channels, "Get OCs 4" );
    is( scalar @ocs, 1, "Check for 1 OC 4" );
    is( $ocs[0]->get_name, $ocname, "Check OC name 4" );
}
##############################################################################
# Test output channel associations.
##############################################################################

sub test_alias : Test(28) {
    my $self = shift;
    throws_ok {
        Bric::Biz::Asset::Business::Story->new({})
      } qr/Cannot create an asset without an element or alias ID/,
        "Check that you cannot create empty stories";

    throws_ok {
        Bric::Biz::Asset::Business::Story->new(
          { alias_id => 1, element__id => 1});
    } qr/Cannot create an asset with both an element and an alias ID/,
      "Check that you cannot create a story with both element__id and an ".
      "alias";

    throws_ok {
        Bric::Biz::Asset::Business::Story->new(
          { alias_id => 1, element => 1});
    } qr/Cannot create an asset with both an element and an alias ID/,
      "Check that you cannot create a story with both element and an ".
      "alias";


    ok( my $story = Bric::Biz::Asset::Business::Story->new(
      { element       => $self->get_elem,
        user__id      => $self->user_id,
        name          => 'Victor',
        slug          => 'hugo',
        source__id    => 1,
        site_id       => 100,
      }), "Construct story" );

    $story->add_categories( [ $CATEGORY ] );
    $story->set_primary_category($CATEGORY);

    ok( $story->save, "Save story" );


    # Save the ID for cleanup.
    ok( my $sid = $story->get_id, "Get ID" );
    my $key = $self->class->key_name;
    $self->add_del_ids($sid, $key);

    ok( $story = Bric::Biz::Asset::Business::Story->lookup
        ({id => $story->get_id }), "Reload");

    throws_ok {
        Bric::Biz::Asset::Business::Story->new(
          { alias_id => $story->get_id })
      } qr /Cannot create an asset without a site/,
        "Check that you need the Site parameter";

    throws_ok {
        Bric::Biz::Asset::Business::Story->new(
          { alias_id => $story->get_id, site_id => 100 })
      } qr /Cannot create an alias to an asset in the same site/,
        "Check that you cannot create alias to a story in the same site";

    # Create extra site
    my $site1 = Bric::Biz::Site->new( { name => __PACKAGE__ . "1",
                                        domain_name => __PACKAGE__ . "1",
                                      });

    ok( $site1->save(), "Create first dummy site");
    my $site1_id = $site1->get_id;
    $self->add_del_ids($site1_id, 'site');

    throws_ok {
        Bric::Biz::Asset::Business::Story->new
           ({ alias_id => $story->get_id, site_id => $site1_id })
      } qr/Cannot create an alias to an asset based on an element that is not associated with this site/,
        "Check that a element needs to be associated with a site ".
        "for a target to aliasable";

    my $element = $story->_get_element_object();
    $element->add_sites([$site1]);
    $element->save();

    throws_ok {
        Bric::Biz::Asset::Business::Story->new
          ({ alias_id => $story->get_id, site_id => $site1_id })
      } qr /Cannot create an alias to this asset because this element has no output channels associated with this site/,
        "Check that the element associated to alias target has any output ".
        "channels for this site";

    #Lets create an output channel here

    # Add a new output channel.
    ok( my $oc = Bric::Biz::OutputChannel->new({name    => __PACKAGE__ . "1",
                                                site_id => $site1_id}),
        "Create OC" );
    ok( $oc->save, "Save OC" );
    ok( my $ocid = $oc->get_id, "Get OC ID" );
    $self->add_del_ids($ocid, 'output_channel');

    $element->add_output_channels([$ocid]);
    $element->set_primary_oc_id($ocid, $site1_id);
    $element->save();

    ok( my $alias_story = Bric::Biz::Asset::Business::Story->new(
      { alias_id => $story->get_id, 
        site_id  => $site1_id,
        user__id => $self->user_id,
      }),
        "Create an alias story");

    isnt($alias_story->_get_element_object,
         undef, "Check that we get a element object");

    is($alias_story->_get_element_object->get_id,
       $story->_get_element_object->get_id,
       "Check that alias_story has a element object");

    ok( $alias_story->save , "Try to save it");
    my $alias_id = $alias_story->get_id;
    like($alias_id, qr/^\d+$/, "alias id should be a number");

    ok( $alias_story = 
        Bric::Biz::Asset::Business::Story->lookup
        ( { id => $alias_id }),
        "Refetch the alias");
    isa_ok($alias_story, "Bric::Biz::Asset::Business::Story", "Checking that ".
          "we got $alias_id back");
#    sleep;
    is($alias_story->get_alias_id, $story->get_id,
       "Does it still point to the correct story");


    is($alias_story->get_slug, $story->get_slug, "Check slug");

    is_deeply($story->get_tile, $alias_story->get_tile,
              "Should get identical tiles");

    is_deeply([$alias_story->get_all_keywords],
              [$story->get_all_keywords],
              "Check get_all_keywords");

    is_deeply([$alias_story->get_keywords],
              [$story->get_keywords],
              "Check get_keywords");

    is_deeply([$alias_story->get_contributors],
              [$story->get_contributors],
              "Check get_contributors");

    $element->remove_sites([$site1]);
    $element->save();


    Bric::Util::DBI::prepare(qq{
        DELETE FROM element__site
        WHERE  site__id = $site1_id
    })->execute;

    Bric::Util::DBI::prepare(qq{
        DELETE FROM story
        WHERE  site__id = $site1_id
    })->execute;

}

1;
__END__
