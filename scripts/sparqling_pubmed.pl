# Correlates Ensembl IDs (and later on, xrefs) with PubMed beta Sparql endpoint

use Modern::Perl;
use LWP::UserAgent;
use JSON;
use URI::Escape;
use RDF::Query::Client;
use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::RDF::RDFlib;
use Bio::EnsEMBL::RDF::EnsemblToIdentifierMappings;
use Time::HiRes qw/gettimeofday tv_interval/;
use IO::File;
my $debug;
my $uri = 'http://wwwdev.ebi.ac.uk/rdf/services/textmining/sparql';
# my $content_type = 'x-www-form-urlencoded';
# my $accept = 'application/sparql-results+json';
my $chromosome = shift;
my $filename = shift;
die "Specify seq region name\n" unless $chromosome;
$filename ||= 'hits_uris.txt';

my $lwp = LWP::UserAgent->new();
$lwp->agent('ensembl-xref (Linux, perl/5.14.2)');

Bio::EnsEMBL::Registry->load_registry_from_db(
  -host => 'mysql-ensembl-mirror.ebi.ac.uk',
  -user => 'anonymous',
  -port => 4240,
  # -host => 'asiadb.ensembl.org',
  # -user => 'anonymous',
  # -port => 5306,
  -db_version => 81,
  );
print "Connected to Ensembl\n";
my $fh = IO::File->new($filename,'w');
my $converter = Bio::EnsEMBL::RDF::EnsemblToIdentifierMappings->new('../xref_LOD_mapping.json');

my $sparql_prefix = compatible_name_spaces();

my $sparql_start = '
SELECT ?prefix ?exact ?postfix ?section ?source WHERE {
  ?annotation oa:hasBody ?xref .
  ?annotation oa:hasTarget ?target .
  ?target oa:hasSource ?source .
  ?target oa:hasSelector ?selector .
  ?target dcterms:isPartOf ?section .
  ?selector oa:prefix ?prefix .
  ?selector oa:exact ?exact .
  ?selector oa:postfix ?postfix .
';
my $sparql_end = '}';
my $gene_adaptor = Bio::EnsEMBL::Registry->get_adaptor('Human','core','Gene');
my $slice_adaptor = Bio::EnsEMBL::Registry->get_adaptor( "human", "core", "slice" );
my $slice = $slice_adaptor->fetch_by_region( 'chromosome', $chromosome );
my $genes = $gene_adaptor->fetch_all_by_Slice($slice);
my $sparql;
my $hits = 0;
my @lits;
print "Querying Pubmed beta with ".scalar @$genes." Ensembl genes\n"; 
my $e_progress = 0;
my $pub_progress = 0;

my %white_list = ( 
  'http://identifiers.org/ensembl/' => 1,
  'http://identifiers.org/ena.embl/' => 1,
  'http://identifiers.org/uniprot/' => 1,
  'http://identifiers.org/pdb/' => 1,
  'http://identifiers.org/interpro/' => 1,
  'http://identifiers.org/pfam/' => 1,
  'http://identifiers.org/arrayexpress/' => 1,
  'http://identifiers.org/omim/' => 1,
  'http://identifiers.org/refseq/' => 1,
  'http://identifiers.org/dbsnp/' => 1
);

my %xrefs_tried;

my $start_time = [gettimeofday()];
while ( my $gene = shift @$genes) {
  my @xrefs = @{ $gene->get_all_DBLinks };
  print "Gene: ".$gene->stable_id." has ".@xrefs." xrefs\n";
  my @xref_names;
  foreach my $xref (@xrefs) {
    if ($debug && !exists $xrefs_tried{$xref->dbname}) {
      print "New e! Xref: ".$xref->dbname."\n"; 
      $xrefs_tried{$xref->dbname} = 1
    }
    my $id_org_uri = $converter->identifier_org_translation($xref->dbname);
    if ( $id_org_uri && exists $white_list{$id_org_uri}) {
      # print "Wee, got an $id_org_uri\n" if $debug;
      push @xref_names,$id_org_uri.$xref->display_id;
    } # Some external DB names don't map to LOD URIs.
  }
  my @collected_hits;
  if (@xref_names > 0) {
    @xref_names = unique(@xref_names);
    my @few_names = splice(@xref_names,0,3);
    while ( @few_names > 0 ) {

      my $sparql_values = sprintf 'VALUES ?xref {%s}',join(' ', map { qq{<$_>} } @few_names);
      $sparql = $sparql_prefix . $sparql_start . $sparql_values . $sparql_end;
      if ($debug) {print "DEBUG: $sparql"}
      my $query = RDF::Query::Client->new($sparql, {UserAgent => $lwp});
      my @results = $query->execute($uri);
      print ".";
      if (!$query->error) {
        push @collected_hits,@results;
      } else {
        die "Error from Pubmed SPARQL server: ".$query->error."\n Data: $sparql, ".$gene->stable_id;
      }
      @few_names = splice(@xref_names,0,3);
    }
  }
  $e_progress++;

  while (my $row = shift @collected_hits) {
    printf "%s via %s gives: %s",$gene->stable_id,$row->{exact},$row->{source}->as_string."\n";
    printf $fh "%s\t%s\t%s\t%s\n",$gene->stable_id,$row->{exact},$row->{source}->as_string,$row->{section}->as_string;
    $pub_progress++;
    if ($pub_progress % 100 == 0) {
      print "Found $pub_progress PubMed entries\n";
    }
  }

  print "\n";
  if ($e_progress % 100 == 0) {
    print "Processed $e_progress Ensembl IDs\n";
  }
}
  
my $elapsed = tv_interval ( $start_time, [gettimeofday()]);
$fh->close;

printf "\nTotal of %s Ensembl genes searched for in Pubmed beta\n",$e_progress;
printf "Total time is %.2f seconds\n",$elapsed;
printf "Matched %d times to PubMed articles\n",$pub_progress;
print "Finished\n";

sub unique {
  my %hash = map { $_, 1 } @_;
  return keys %hash;
}
