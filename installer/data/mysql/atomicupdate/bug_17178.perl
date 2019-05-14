$DBversion = 'XXX'; # will be replaced by the RM
if( CheckVersion( $DBversion ) ) {
    # you can use $dbh here like:
    # $dbh->do( "ALTER TABLE biblio ADD COLUMN badtaste int" );

    # or perform some test and warn
    # if( !column_exists( 'biblio', 'biblionumber' ) ) {
    #    warn "There is something wrong";
    # }
    $dbh->do( 'INSERT INTO keyboard_shortcuts (shortcut_name, shortcut_keys) VALUES ("toggle_keyboard", "Ctrl-K")');

    # Always end with this (adjust the bug info)
    SetVersion( $DBversion );
    print "Upgrade to $DBversion done (Bug 17178 - add shortcut to keyboard_shortcuts)\n";
}
