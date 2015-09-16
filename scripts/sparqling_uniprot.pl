# Without optimisation, requires 6 hours to do 100 IDs. There are 90k of them.

use Modern::Perl;
use LWP::UserAgent;
use JSON;
use URI::Escape;
use RDF::Query::Client;
use Bio::EnsEMBL::Registry;

my $uri = 'http://sparql.uniprot.org/sparql/';
# my $content_type = 'x-www-form-urlencoded';
# my $accept = 'application/sparql-results+json';

my $lwp = LWP::UserAgent->new();
$lwp->agent('ensembl-xref  (Linux, perl/5.14.2)');

my $sparql_start = 'PREFIX rdfs:<http://www.w3.org/2000/01/rdf-schema#> 
PREFIX up:<http://purl.uniprot.org/core/> 
PREFIX uniprotkb:<http://purl.uniprot.org/uniprot/> 
PREFIX taxon:<http://purl.uniprot.org/taxonomy/> 
PREFIX rdf:<http://www.w3.org/1999/02/22-rdf-syntax-ns#> 
PREFIX database:<http://purl.uniprot.org/database/>
SELECT ?protein ?ensembl ?xref ?reviewed
WHERE {
 VALUES (?ensembl ?sequence) {
  ';
   
my $sparql_end = '} .
  ?protein up:sequence/rdf:value ?sequence ;
            up:organism taxon:9606 ;
            rdfs:seeAlso ?xref ;
      up:reviewed ?reviewed .
  ?xref up:database ?database .
  FILTER (?database NOT IN (database:Ensembl))
}';

Bio::EnsEMBL::Registry->load_registry_from_db(
  -host => 'mysql-ensembl-mirror.ebi.ac.uk',
  -user => 'anonymous',
  -port => 4240,
  -db_version => 81,
  );
print "Connected to Ensembl";
my $transcript_adaptor = Bio::EnsEMBL::Registry->get_adaptor('Human','core','Transcript');
my $transcripts =  $transcript_adaptor->fetch_all();
my @coding_transcripts = sort { $a->translate->seq cmp $b->translate->seq} grep {$_->translate} @$transcripts;
print @coding_transcripts." found in database\n";
my $sparql;
my $max = 99;
while ( @coding_transcripts > 0) {
  $sparql = $sparql_start . join("\n",map { sprintf "('%s' '%s')",$_->stable_id,$_->translate->seq->seq } splice(@coding_transcripts,0,$max) ) . $sparql_end;
  $max = @coding_transcripts if ( @coding_transcripts < $max);

  my $query = RDF::Query::Client->new($sparql, {UserAgent => $lwp});
  print "Querying Uniprot\n"; 
  my @results = $query->execute($uri);
  print @results." hits\n";
  while (my $row = shift @results) {
    print $row->{protein}->as_string;
  }
}
print "Finished\n";
