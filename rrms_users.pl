#!/usr/bin/perl
########################################################################
# Description: Manage users allowed to manipulate EMC rewrite rules.
# Parameters : -c <Create>, -d <Delete>, -p <Change Password>, -l <List>
# Returns    : 0 on Success or 1 on Error.
# Author     : Khaled Ahmed <khaled.ahmed@emc.com>
########################################################################

use strict;
use Cwd 'abs_path';
use File::Basename;

our $absolute_path   = dirname(abs_path($0))."/";
our $rrms_confdir    = $absolute_path."conf/";

our $baseDir="";
our $salt = '*FAKESALT*';
our $param = $ARGV[0];
our $digest;

open(PASSFILE,$rrms_confdir."accounts");
our @USERS = <PASSFILE>;
close PASSFILE;


if ($param eq "-c"){
    print "Username: ";
    my $username = <STDIN>;
    chomp($username);
    print "Password: ";
    system "stty -echo";
    my $password = <STDIN>;
    chomp($password);
    system "stty echo";
    print "\n";
    print "Retype Password: ";
    system "stty -echo";
    my $repassword = <STDIN>;
    chomp($repassword);
    system "stty echo";
    print "\n";
    
    if ($password ne $repassword){
        print STDERR "Password didn't match\n";
        exit(1);
    }

    print "Full Name: ";
    my $fullname = <STDIN>;
    chomp($fullname);
    
    
    $digest = crypt($password,$salt);
    
    my $user = $username.":".$fullname.":".$digest."\n";
    
    if (grep {/$username/} @USERS){
        print STDERR "Error: ".$username." already exists.\n";
        exit(1);
    }
    
    push(@USERS,$user);
    
    open(PASSFILE,">",$rrms_confdir."accounts");
    print PASSFILE @USERS;
    close(PASSFILE);
    
    print "User ".$username." Created\n";
    exit(0);
    
}elsif($param eq "-ic"){
	
	my $username = $ARGV[1];
	my $password = $ARGV[2];
	my $fullname = $ARGV[3];
	my $digest = crypt($password,$salt);
	my $user = $username.":".$fullname.":".$digest."\n";
	
	if (grep {/$username/} @USERS){
        	print STDERR "Error: ".$username." already exists.\n";
        	exit(1);
    	}

	push(@USERS,$user);

    open(PASSFILE,">",$rrms_confdir."accounts");
    print PASSFILE @USERS;
    close(PASSFILE);

    print "User ".$username." Created\n";
    exit(0);

}elsif ($param eq "-d"){
    
    print "User to delete: ";
    my $username = <STDIN>;
    chomp($username);
    
    foreach (@USERS){
        if (/$username/){
            $_ = "";
        }
    }
    
    open(PASSFILE,">",$rrms_confdir."accounts");
    print PASSFILE @USERS;
    close(PASSFILE);
    
    print "User ".$username." Deleted\n";
    exit(0);
    

}elsif($param eq "-id"){

	my $username = $ARGV[1];
	
	    foreach (@USERS){
        if (/$username/){
            $_ = "";
        }
    }

    open(PASSFILE,">",$rrms_confdir."accounts");
    print PASSFILE @USERS;
    close(PASSFILE);

    print "User ".$username." Deleted\n";
    exit(0);	


}elsif($param eq "-v"){
    my $username = $ARGV[1];
    my $digest = crypt($ARGV[2],$salt);

    foreach (@USERS){
        chomp;
        my ($retUser,$fullName,$retPass) = split(/:/);
    
	if (/$username/){	
        if (/\Q$ARGV[1]\E/ eq /\Q$retUser\E/ and /\Q$digest\E/ eq /\Q$retPass\E/){
           print STDOUT "true\n";
           exit (0);
        }else{
	   print STDOUT "false\n";
	   exit(1);
	}
    }
}

}elsif($param eq "-p"){
    
    print "Username: ";
    my $username = <STDIN>;
    chomp($username);
    
    my $userFound = 0;
    my $pass;

    foreach (@USERS){
        my ($user,$full,$pass) = split(/:/);
        
        if (/\Q$user\E/ eq /\Q$username\E/){
            $userFound = 1;
            $pass = $digest;
        }
    }
    
    if ($userFound == 0){
        print STDERR "Error: user doesn't exist.\n";
        exit(1);
    }
    
    print "Password: ";
    system "stty -echo";
    my $password = <STDIN>;
    chomp($password);
    system "stty echo";
    print "\n";
    print "Retype Password: ";
    system "stty -echo";
    my $repassword = <STDIN>;
    chomp($repassword);
    system "stty echo";
    print "\n";
    
    if ($password ne $repassword){
        print STDERR "Password didn't match\n";
        exit(1);
    }
    my $digest = crypt($password,$salt);
    
    foreach (@USERS){
        my ($user,$full,$pass) = split(/:/);
        
        if (/\Q$user\E/ eq /\Q$username\E/){
            $pass = $digest;
            $_ = $user.":".$full.":".$digest."\n";
        }
    }
    
    open (PASSFILE,">",$rrms_confdir."accounts");
    print PASSFILE @USERS;
    close(PASSFILE);
    
    print "Password changed for user ".$username."\n";


}elsif($param eq "-ip"){

	my $username = $ARGV[1];
	my $password = $ARGV[2];
	my $userFound = 0;
	my $pass;
	my $digest = crypt($password,$salt);

    foreach (@USERS){
        my ($user,$full,$pass) = split(/:/);

        if (/\Q$user\E/ eq /\Q$username\E/){
            $userFound = 1;
            $pass = $digest;
        }
    }

    if ($userFound == 0){
        print STDERR "Error: user doesn't exist.\n";
        exit(1);
    }
	

	foreach (@USERS){
        my ($user,$full,$pass) = split(/:/);

        if (/\Q$user\E/ eq /\Q$username\E/){
            $pass = $digest;
            $_ = $user.":".$full.":".$digest."\n";
        }
    }

    open (PASSFILE,">",$rrms_confdir."accounts");
    print PASSFILE @USERS;
    close(PASSFILE);

    print "Password changed for user ".$username."\n";


}elsif( $param eq "-l" ){

	foreach(@USERS){
		my ($uname,$fullname,$pwd) = split(/:/);
		print $uname." (".$fullname.")\n";
	}

}else{
    Usage();
}

sub Usage{
    
    print "USAGE: 'rrms_users -c' to create new user\n";
    print "       'rrms_users -p' to change the user's password\n";
    print "       'rrms_users -d' to delete an existing user\n";
    print "       'rrms_users -l' to list existing users\n";
    exit(0)
}
