#!/usr/bin/perl

use strict;
use Spreadsheet::XLSX;

my $excel = Spreadsheet::XLSX->new($ARGV[0]);
our $cell1;
our $cell2;
our $cell3;
our $xlsRtype;
our $xlsRsrc;

foreach my $sheet (@{$excel->{Worksheet}}) {
    $sheet->{MinRow} ||= $sheet->{MaxRow};
    foreach my $row ($sheet->{MinRow} .. $sheet->{MaxRow}) {
        $sheet->{MaxCol} ||= $sheet->{MinCol};
        if ($row != 1){
            	 $cell1 = $sheet->{Cells}[$row][5];
            	 $cell2 = $sheet->{Cells}[$row][6];
            	 $cell3 = $sheet->{Cells}[$row][7];
		 if ($cell1){
		    $xlsRsrc = $cell1->value();  
		    $xlsRsrc =~ tr/A-Z/a-z/;
		    if ($cell2){
			if ($cell3){	
			   if ($cell3->value() =~ /yes/i){
					$xlsRtype = "vanity";	
			    }else{
					$xlsRtype = "redirect";
			   }
               		print($xlsRsrc."  ".$cell2->value()."  ".$xlsRtype."\n");
			   }
	        }
         }
      }
   }
}
