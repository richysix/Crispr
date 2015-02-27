#!/usr/bin/env perl
# plate.t

use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use DateTime;

my $date_obj = DateTime->now();
my $todays_date = $date_obj->ymd;

plan tests => 30 + 1 + 3 + 5 + 5 + 4 + 3 + 3 + 3 + 4 + 4 + 3 + 9 + 1 + 6 + 3 + 6 + 2 + 4 + 384;

use Crispr::Plate;

# make a plate object with no attributes
my $plate = Crispr::Plate->new();

# check method calls 30 tests
my @methods = qw( plate_name plate_type wells fill_direction number_of_columns
 _row_name_for _row_names number_of_rows number_of_columns check_well_id_validity
 _split_well_id _check_row_name_validity _check_column_name_validity _row_name_to_index _col_name_to_index
 add_well add_wells fill_well fill_wells_from_starting_well well_id_to_indices
 next_well_id _increment_by_row _increment_by_column _indices_to_well_id _indices_to_well_number
 _build_empty_wells plate_id plate_category ordered received
);

foreach my $method ( @methods ) {
    can_ok( $plate, $method );
}

my $plate_2 = Crispr::Plate->new(
    plate_id => 1,
    plate_name => 'CR-000002b',
    plate_type => '96',
    plate_category => 'cloning_oligos',
    fill_direction => 'row',
    ordered => '2013-06-07',
    received => '2013-06-07',
);

# new 384 well plate
my $plate_3 = Crispr::Plate->new(
    plate_name => 'CR-000003a',
    plate_type => '384',
    fill_direction => 'column',
    ordered => $date_obj,
    received => $date_obj,
);

# check it accommodates calling with hashref - 1 test
my %args = (
    plate_name => 'CR-000003a',
    plate_type => '384',
    fill_direction => 'column',
    ordered => '2013-06-07',
    received => $date_obj,
);
isa_ok( Crispr::Plate->new( \%args ), 'Crispr::Plate', 'HashRef calling style' );

# check class - 3 tests
isa_ok( $plate, 'Crispr::Plate' );
isa_ok( $plate_2, 'Crispr::Plate' );
isa_ok( $plate_3, 'Crispr::Plate' );

# name attribute - 5 tests
is( $plate->plate_name, undef, 'Get plate_name' );
is( $plate->plate_name('CR-000001a'), 'CR-000001a', 'Set plate_name' );
is( $plate_2->plate_name, 'CR-000002b', 'Get plate_name 2' );
is( $plate_2->plate_name('CR-000002a'), 'CR-000002a', 'Set plate_name 2' );
is( $plate_3->plate_name, 'CR-000003a', 'Get plate_name 3' );

# plate type - 5 tests
is( $plate->plate_type, '96', 'Get default plate_type' );
is( $plate_2->plate_type, '96', 'Get plate_type 2' );
is( $plate_3->plate_type, '384', 'Get plate_type 3' );
throws_ok{ $plate->plate_type('384') } qr/read-only accessor/, 'try changing ro plate_type';
throws_ok{ Crispr::Plate->new( plate_type => '192') } qr/Validation failed/, 'test plate_type type-constraint';

# wells - 4 tests
isa_ok( $plate->wells, 'ARRAY', 'Get default wells 1');
isa_ok( $plate_2->wells, 'ARRAY', 'Get wells 2');
isa_ok( $plate_3->wells, 'ARRAY', 'Get default wells 3');
isa_ok( $plate_2->wells->[0], 'ARRAY', 'Get well class 2.1');

# fill_direction - 3 tests
is( $plate->fill_direction, 'column', 'Get default fill_direction' );
is( $plate_2->fill_direction, 'row', 'Get fill_direction 2' );
is( $plate_3->fill_direction, 'column', 'Get fill_direction 3' );

# Crispr specific attributes
# plate_id - 3 tests
is( $plate->plate_id, undef, 'Get default plate_id' );
is( $plate_2->plate_id, 1, 'Get plate_id 2' );
throws_ok{ Crispr::Plate->new( plate_id=> 'string') } qr/Validation failed/, 'Try setting plate_id to string';

# plate_category - 3 tests
is( $plate->plate_category, undef, 'Get default plate_category 1' );
is( $plate_2->plate_category, 'cloning_oligos', 'Get plate_category 2' );
throws_ok{ Crispr::Plate->new( plate_category => 'expression', ) } qr/Validation failed/, 'Set plate_category to incorrect value'; 

# ordered - 4 tests
is( $plate->ordered, undef, 'Get default ordered 1' );
is( $plate_2->ordered, '2013-06-07', 'Get ordered 2' );
is( $plate_3->ordered, $todays_date, 'Get ordered 3 - set by DateTime obj' );
throws_ok{ Crispr::Plate->new( ordered => '2013', ) } qr/The date supplied is not a valid format/, 'Set ordered to incorrect value'; 

# received - 4 tests
is( $plate->received, undef, 'Get default received 1' );
is( $plate_2->received, '2013-06-07', 'Get received 2' );
is( $plate_3->received, $todays_date, 'Get received 2' );
throws_ok{ Crispr::Plate->new( received => '2013', ) } qr/The date supplied is not a valid format/, 'Set received to incorrect value'; 

# methods 
# add real well
use Labware::Well;
my $well = Labware::Well->new(
    plate_type => '96',
    position => 'A01',
    contents => 'String contents',
);
# add and return a single well - 3 tests
$plate->add_well( $well );
is( $plate->return_well('A01')->position, 'A01', 'Add single well - Position of returned well');
is( $plate->return_well('A01')->plate_type, '96', 'Add single well - Plate type of returned well');
is( $plate->return_well('A01')->contents, 'String contents', 'Add single well - contents of returned well');

# add several wells
my @wells;
for ( my $i = 3; $i < 12; $i+=3 ){
    my $well_id = 'A' . $i;
    my $well = Labware::Well->new(
        plate_type => '96',
        position => $well_id,
        contents => $well_id,
    );
    push @wells, $well;
}
$plate->add_wells( \@wells );
# 9 tests
for ( my $i = 3; $i < 12; $i+=3 ){
    my $id = 'A' . $i;
    my $well_id = $id;
    substr( $well_id, 1, 0, '0');
    is( $plate->return_well($id)->position, $well_id, 'add several wells - Position of returned well');
    is( $plate->return_well($id)->plate_type, '96', 'add several wells - Plate type of returned well');
    is( $plate->return_well($id)->contents, $id, 'add several wells - contents of returned well');
}

# try to add a well to an already filled well - 1 test
throws_ok { $plate->add_well( $well ) } qr/Well is not empty!/, 'Attempt to fill an already filled well';

# add column of wells
@wells = ();
foreach ( qw( A B C D E F G H ) ){
    my $well_id = $_ . '05';
    my $well = Labware::Well->new(
        plate_type => '96',
        position => $well_id,
        contents => $well_id,
    );
    push @wells, $well;
}
$plate->add_wells( \@wells );
# 6 tests
foreach ( qw( A D H ) ){
    my $well_id = $_ . '05';
    is( $plate->return_well($well_id)->position, $well_id, 'add column of wells - Position of returned well');
    is( $plate->return_well($well_id)->contents, $well_id, 'add column of wells - contents of returned well');
}


my @stuff = qw{ stuffb1 stuffc1 stuffd1 stuffe1 };

# fill single well - 3 tests
$plate->fill_well( $stuff[0], 'B01' );
is( $plate->return_well('B01')->position, 'B01', 'fill single well - Position of returned well B01');
is( $plate->return_well('B01')->plate_type, '96', 'fill single well - Plate type of returned well B01');
is( $plate->return_well('B01')->contents, 'stuffb1', 'fill single well - contents of returned well B01');

# fill several wells - 6 tests
my @list_of_contents = @stuff[1..3];
$plate->fill_wells_from_starting_well( \@list_of_contents, 'C01' );
is( $plate->return_well('D01')->position, 'D01', 'fill several wells - Position of returned well D01');
is( $plate->return_well('D01')->plate_type, '96', 'fill several wells - Plate type of returned well D01');
is( $plate->return_well('D01')->contents, 'stuffd1', 'fill several wells - contents of returned well D01');

@list_of_contents = qw{ row-wise-a1 row-wise-a2 row-wise-a3 row-wise-a4 row-wise-a5 row-wise-a6
row-wise-a7 row-wise-a8 row-wise-a9 row-wise-a10 row-wise-a11 row-wise-a12 };
$plate_2->fill_wells_from_starting_well( \@list_of_contents, 'A01' );
is( $plate_2->return_well('A04')->position, 'A04', 'Fill wells row-wise - Position of returned well A04');
is( $plate_2->return_well('A04')->plate_type, '96', 'Fill wells row-wise - Plate type of returned well A04');
is( $plate_2->return_well('A04')->contents, 'row-wise-a4', 'Fill wells row-wise - contents of returned well A04');

# find next empty well id - 2 tests
is( $plate->first_empty_well_id, 'F01', 'Get first empty well id');
is( $plate_2->first_empty_well_id, 'B01', 'Get first empty well id row-wise');

# fill wells from first empty well - 4 tests
@list_of_contents = qw( stuff-1 stuff-2 stuff-3 );
$plate->fill_wells_from_first_empty_well( \@list_of_contents );
is( $plate->return_well('F01')->contents, 'stuff-1', 'fill single well - contents of returned well F01');
is( $plate->return_well('G01')->contents, 'stuff-2', 'fill single well - contents of returned well G01');
is( $plate->return_well('H01')->contents, 'stuff-3', 'fill single well - contents of returned well H01');
is( $plate->first_empty_well_id, 'A02', 'Get first empty well id');

my $returned_wells = $plate->return_all_wells;
#map { print join("\t", $_->position, $_->contents), "\n" } @{$returned_wells};
my $plate_4 = Crispr::Plate->new(
    plate_name => 'CR-000004a',
    plate_type => '96',
    fill_direction => 'column',
);
my $plate_5 = Crispr::Plate->new(
    plate_name => 'CR-000004a',
    plate_type => '96',
    fill_direction => 'row',
);
my @list = ( 1..96 );
$plate_4->fill_wells_from_first_empty_well( \@list );
$plate_5->fill_wells_from_first_empty_well( \@list );
$returned_wells_2 = $plate_4->return_all_wells;
$returned_wells_3 = $plate_5->return_all_wells;
my $wrong = 0;
my @row_names = qw{A B C D E F G H};
my @column_names = qw{ 01 02 03 04 05 06 07 08 09 10 11 12 };
my ( $rowi, $coli );
# 4 * 96 - 384 tests
for ( 1..96 ){
    my $well = shift @{$returned_wells_2};
    ( $rowi, $coli ) = $plate_4->_well_number_to_indices( $_ );
    is( $well->position, $row_names[$rowi] . $column_names[$coli], "well $_ position - column-wise" );
    is( $well->contents, $_, "well $_ contents - column-wise" );
    
    my $well_2 = shift @{$returned_wells_3};
    ( $rowi, $coli ) = $plate_5->_well_number_to_indices( $_ );
    is( $well_2->position, $row_names[$rowi] . $column_names[$coli], "well $_ position - row-wise" );
    is( $well_2->contents, $_, "well $_ contents - row-wise" );
}

#$plate_4->print_all_wells("\t", \*STDOUT );
