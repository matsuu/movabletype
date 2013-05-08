#!/usr/bin/perl

use strict;
use warnings;

use lib qw(lib t/lib ../lib);

BEGIN {
    $ENV{MT_CONFIG} = 'mysql-test.cfg';
}

use IPC::Open2;

use Test::Base;
plan tests => 2 * blocks;

use MT;
use MT::Test qw(:app :db);
my $app = MT->instance;

my $blog_id = 1;    # First Website

filters {
    template => [qw( chomp )],
    expected => [qw( chomp )],
};

my $mt    = MT->instance;
my $admin = MT->model('author')->load(1);    # Administrator

{
    # Parent website
    my $w = $mt->model('website')->load($blog_id);
    $w->set_values(
        {   description => 'This is a first website.',
            site_url    => 'http://localhost/first_website/',
            site_path   => '/var/www/html/first_website',
            cc_license =>
                'by http://creativecommons.org/licenses/by/3.0/ http://i.creativecommons.org/l/by/3.0/88x31.png',
        }
    );
    $w->save or die $w->errstr;

    # apply theme
    $app = _run_app(
        'MT::App::CMS',
        {   __test_user      => $admin,
            __request_method => 'POST',
            __mode           => 'apply_theme',
            blog_id          => $w->id,
            theme_id         => 'classic_website',
        },
    );

    # Create entries
    my $e1 = $mt->model('entry')->new;
    $e1->set_values(
        {   blog_id     => $blog_id,
            author_id   => $admin->id,
            status      => MT::Entry::RELEASE(),
            title       => 'Website Entry 1',
            basename    => 'website_entry_1',
            text        => 'This is website entry 1.',
            text_more   => 'Both allow_pings and allow_comments are null.',
            excerpt     => 'Website Entry Excerpt 1',
            keywords    => 'Foo',
            authored_on => '2011-01-01 00:00:00',
        }
    );
    $e1->save or die $e1->errstr;

    my $tmpl
        = MT::Template->load( { blog_id => $blog_id, type => 'individual' } );

    require MT::PublishOption;
    my $tm1 = MT::TemplateMap->new;
    $tm1->set_values(
        {   archive_type => 'Individual',
            blog_id      => $admin->id,
            build_type   => MT::PublishOption::DYNAMIC(),
            is_preferred => 1,
            template_id  => $tmpl->id,
        }
    );
    $tm1->save or die $tm1->errstr;

    my $fi1 = MT::FileInfo->new;
    $fi1->set_values(
        {   archive_type => 'Individual',
            blog_id      => $admin->id,
            entry_id     => $e1->id,
            file_path =>
                '/var/www/html/first_website/2011/01/website-entry-1.html',
            template_id    => $tmpl->id,
            templatemap_id => $tm1->id,
            url =>
                'http://localhost/first_website/2011/01/website-entry-1.html',
            virtual => 1,
        }
    );
    $fi1->save or die $fi1->errstr;

    # allow_pings is set 1.
    my $e2 = $mt->model('entry')->new;
    $e2->set_values(
        {   blog_id     => $blog_id,
            author_id   => $admin->id,
            status      => MT::Entry::RELEASE(),
            title       => 'Website Entry 2',
            basename    => 'website_entry_2',
            text        => 'This is website entry 2.',
            text_more   => 'Allow_pings is 1, allow_comments is null.',
            excerpt     => 'Website Entry Excerpt 2',
            allow_pings => 1,
            authored_on => '2012-02-02 00:00:00',
        }
    );
    $e2->save or die $e2->errstr;

    # allow_comments is set 1.
    my $e3 = $mt->model('entry')->new;
    $e3->set_values(
        {   blog_id        => $blog_id,
            author_id      => $admin->id,
            status         => MT::Entry::RELEASE(),
            title          => 'Website Entry 3',
            basename       => 'website_entry_3',
            text           => 'This is website entry 3.',
            text_more      => 'Allow_pings is null, allow_comments is 1.',
            excerpt        => 'Website Entry Excerpt 3',
            allow_comments => 1,
            keywords       => 'Bar',
            authored_on    => '2013-03-03 00:00:00',
        }
    );
    $e3->save or die $e3->errstr;

    # status is set 1 (HOLD).
    my $e4 = $mt->model('entry')->new;
    $e4->set_values(
        {   blog_id          => $blog_id,
            author_id        => $admin->id,
            status           => MT::Entry::HOLD(),
            title            => 'Website Entry 4',
            text             => 'This is website entry 4.',
            authored_on_date => '2014-04-04',
        }
    );
    $e4->save or die $e4->errstr;
}

{
    # Child blog
    my $b = $mt->model('blog')->new;
    $b->set_values(
        {   author_id => $admin->id,
            parent_id => $blog_id,
            name      => 'First Blog',
        }
    );
    $b->save or die $b->errstr;

    my $e1 = $mt->model('entry')->new;
    $e1->set_values(
        {   blog_id   => $b->id,
            author_id => $admin->id,
            status    => MT::Entry::RELEASE(),
            title     => 'Blog Entry 1',
        }
    );
    $e1->save or die $e1->errstr;
}

run {
    my $block = shift;

SKIP:
    {
        skip $block->skip, 1 if $block->skip;

        my $tmpl = $app->model('template')->new;
        $tmpl->text( $block->template );
        my $ctx = $tmpl->context;

        my $blog = MT::Blog->load($blog_id);
        $ctx->stash( 'blog',          $blog );
        $ctx->stash( 'blog_id',       $blog->id );
        $ctx->stash( 'local_blog_id', $blog->id );
        $ctx->stash( 'builder',       MT::Builder->new );

        my $result = $tmpl->build;
        $result =~ s/^(\r\n|\r|\n|\s)+|(\r\n|\r|\n|\s)+\z//g;

        is( $result, $block->expected, $block->name );
    }
};

sub php_test_script {
    my ( $template, $text ) = @_;
    $text ||= '';

    my $test_script = <<PHP;
<?php
\$MT_HOME   = '@{[ $ENV{MT_HOME} ? $ENV{MT_HOME} : '.' ]}';
\$MT_CONFIG = '@{[ $app->find_config ]}';
\$blog_id   = '$blog_id';
\$tmpl = <<<__TMPL__
$template
__TMPL__
;
\$text = <<<__TMPL__
$text
__TMPL__
;
PHP
    $test_script .= <<'PHP';
include_once($MT_HOME . '/php/mt.php');
include_once($MT_HOME . '/php/lib/MTUtil.php');

$mt = MT::get_instance(1, $MT_CONFIG);
$mt->init_plugins();

$db = $mt->db();
$ctx =& $mt->context();

$ctx->stash('blog_id', $blog_id);
$ctx->stash('local_blog_id', $blog_id);
$blog = $db->fetch_blog($blog_id);
$ctx->stash('blog', $blog);

if ($ctx->_compile_source('evaluated template', $tmpl, $_var_compiled)) {
    $ctx->_eval('?>' . $_var_compiled);
} else {
    print('Error compiling template module.');
}

?>
PHP
}

SKIP:
{
    unless ( join( '', `php --version 2>&1` ) =~ m/^php/i ) {
        skip "Can't find executable file: php",
            1 * blocks('expected_dynamic');
    }

    run {
        my $block = shift;

    SKIP:
        {
            skip $block->skip, 1 if $block->skip;

            open2( my $php_in, my $php_out, 'php -q' );
            print $php_out &php_test_script( $block->template, $block->text );
            close $php_out;
            my $php_result = do { local $/; <$php_in> };
            $php_result =~ s/^(\r\n|\r|\n|\s)+|(\r\n|\r|\n|\s)+\z//g;

            my $name = $block->name . ' - dynamic';
            is( $php_result, $block->expected, $name );
        }
    };
}

__END__

=== mt:BlogName
--- template
<mt:BlogID>
--- expected
1

=== mt:BlogName
--- template
<mt:BlogName>
--- expected
First Website

=== mt:BlogDescription
--- template
<mt:BlogDescription>
--- expected
This is a first website.

=== mt:BlogLanguage
--- template
<mt:BlogLanguage>
--- expected
en_US

=== mt:BlogURL
--- template
<mt:BlogURL>
--- expected
http://localhost/first_website/

=== mt:BlogArchiveURL
--- template
<mt:BlogArchiveURL>
--- expected
http://localhost/first_website/

=== mt:BlogRelativeURL
--- template
<mt:BlogRelativeURL>
--- expected
/first_website/

=== mt:BlogSitePath
--- template
<mt:BlogSitePath>
--- expected
/var/www/html/first_website/

=== mt:BlogHost
--- template
<mt:BlogHost>
--- expected
localhost

=== mt:BlogTimezone
--- template
<mt:BlogTimezone>
--- expected
+00:00

=== mt:BlogCCLicenseURL
--- template
<mt:BlogCCLicenseURL>
--- expected
http://creativecommons.org/licenses/by/3.0/

=== mt:BlogCCLicenseImage
--- template
<mt:BlogCCLicenseImage>
--- expected
http://i.creativecommons.org/l/by/3.0/88x31.png

=== mt:CCLicenseRDF
--- template
<mt:CCLicenseRDF>
--- expected
<!--
<rdf:RDF xmlns="http://web.resource.org/cc/"
         xmlns:dc="http://purl.org/dc/elements/1.1/"
         xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
<Work rdf:about="http://localhost/first_website/">
<dc:title>First Website</dc:title>
<dc:description>This is a first website.</dc:description>
<license rdf:resource="http://creativecommons.org/licenses/by/3.0/" />
</Work>
<License rdf:about="http://creativecommons.org/licenses/by/3.0/">
</License>
</rdf:RDF>
-->

=== mt:BlogFileExtension
--- template
<mt:BlogFileExtension>
--- expected
.html

=== mt:BlogTemplateSetID
--- template
<mt:BlogTemplateSetID>
--- expected
classic-website

=== mt:BlogThemeID
--- template
<mt:BlogThemeID>
--- expected
classic-website

=== mt:EntriesCount
--- template
<mt:EntriesCount>
--- expected
3

=== mt:EntryID
--- template
<mt:Entries glue=" "><mt:EntryID></mt:Entries>
--- expected
3 2 1

=== mt:EntryTitle
--- template
<mt:Entries><mt:EntryTitle>
</mt:Entries>
--- expected
Website Entry 3
Website Entry 2
Website Entry 1

=== mt:EntryStatus
--- template
<mt:Entries glue=" "><mt:EntryStatus></mt:Entries>
--- expected
Publish Publish Publish

=== mt:EntryFlag
--- template
<mt:Entries><mt:EntryFlag flag="allow_pings"> <mt:EntryFlag flag="allow_comments">
</mt:Entries>
--- expected
0 1
1 0
0 0

=== mt:EntryBody
--- template
<mt:Entries><mt:EntryBody>

</mt:Entries>
--- expected
This is website entry 3.

This is website entry 2.

This is website entry 1.


=== mt:EntryMore
--- template
<mt:Entries><mt:EntryMore>

</mt:Entries>
--- expected
Allow_pings is null, allow_comments is 1.

Allow_pings is 1, allow_comments is null.

Both allow_pings and allow_comments are null.


=== mt:EntryExcerpt
--- template
<mt:Entries><mt:EntryExcerpt>

</mt:Entries>
--- expected
Website Entry Excerpt 3

Website Entry Excerpt 2

Website Entry Excerpt 1


=== mt:EntryKeywords
--- template
<mt:Entries><mt:EntryKeywords> </mt:Entries>
--- expected
Bar  Foo

=== mt:EntryLink
--- SKIP
--- template
<mt:Entries><mt:EntryLink>
</mt:Entries>
--- expected
http://localhost/first_website/2013/03/website-entry-3.html
http://localhost/first_website/2012/02/website-entry-2.html
http://localhost/first_website/2011/01/website-entry-1.html

=== mt:EntryBasename
--- template
<mt:Entries glue=" "><mt:EntryBasename></mt:Entries>
--- expected
website_entry_3 website_entry_2 website_entry_1

=== mt:EntryAtomID
--- template
<mt:Entries><mt:EntryAtomID>
</mt:Entries>
--- expected
tag:localhost,2013:/first_website//1.3
tag:localhost,2012:/first_website//1.2
tag:localhost,2011:/first_website//1.1

=== mt:EntryPermalink
--- SKIP
--- template
<mt:Entries><mt:EntryPermalink>
</mt:Entries>
--- expected
http://localhost/first_website/2013/03/website-entry-3.html
http://localhost/first_website/2012/02/website-entry-2.html
http://localhost/first_website/2011/01/website-entry-1.html

=== mt:EntryClass
--- template
<mt:Entries glue=" "><mt:EntryClass></mt:Entries>
--- expected
entry entry entry

=== mt:EntryClassLabel
--- template
<mt:Entries glue=" "><mt:EntryClassLabel></mt:Entries>
--- expected
Entry Entry Entry

