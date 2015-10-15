=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 NAME

    EnsemblToTripleConverter - Module to help convert Ensembl data to RDF turtle

=head1 SYNOPSIS

  my $converter = Bio::EnsEMBL::RDF::EnsemblToTripleConverter->new($species,$file_handle);
  $converter->write_to_file('/direct/path/thing.rdf');
  $converter->print_namespaces;
  $converter->print_species_info;


=head1 DESCRIPTION

    Module to provide an API for turning Ensembl features and such into triples
    It relies on the RDFlib Bio::EnsEMB::RDF::RDFlib to provide common functions.

    IMPORTANT - always dump triples using the correct API version for that release

=cut

package Bio::EnsEMBL::RDF::EnsemblToTripleConverter;

use Modern::Perl;
use Bio::EnsEMBL::ApiVersion;
use Bio::EnsEMBL::RDF::RDFlib;
use Bio::EnsEMBL::RDF::EnsemblToIdentifierMappings;
use Bio::EnsEMBL::Utils::SequenceOntologyMapper;
use Carp;
use IO::File;
use Try::Tiny;

# Required args: species, filehandle, , , xref_mapping_file.json
# override release value from API
sub new {
  my ($caller,@args) = @_;
  my ($ontology_adaptor, $meta_adaptor, $species, $fh, $release,$xref_mapping_file) = @args;
  unless ($release) {
    $release = Bio::EnsEMBL::ApiVersion->software_version;
  }
  my $xref_mapping = Bio::EnsEMBL::RDF::EnsemblToIdentifierMappings->new($xref_mapping_file);
  my $biotype_mapper = Bio::EnsEMBL::Utils::SequenceOntologyMapper->new($ontology_adaptor);
  # This connects Ensembl to Identifiers.org amongst other things
  return bless ( {
    ontoa => $ontology_adaptor,
    meta => $meta_adaptor,
    species => $species,
    fh => $fh,
    release => $release,
    taxon => undef,
    ontology_cache => {},
    mapping => $xref_mapping,
    biotype_mapper => $biotype_mapper,
  }, $caller);
}

# getter/setter
sub species {
  my ($self,$species) = @_;
  if ($species) { 
    $self->{species} = $species;
  }
  return $self->{species};
}

#Set a filehandle directly
sub filehandle {
  my ($self,$fh) = @_;
  if ($fh) {
    if ($self->{fh}) {$self->{fh}->close}
    $self->{fh} = $fh;
  }
  return $self->{fh};
}

# Ensembl release version
sub release {
  my ($self,$release) = @_;
  if ($release) {
    $self->{release} = $release;
  }
  return $self->{release};
}

sub ontology_cache {
  my ($self) = @_;
  return $self->{ontology_cache};
}

sub ontology_adaptor {
  my $self = shift;
  return $self->{ontoa};
}

sub meta_adaptor {
  my $self = shift;
  return $self->{meta};
}

sub ensembl_mapper {
  my $self = shift;
  return $self->{mapping};
}

sub biotype_mapper {
  my $self = shift;
  return $self->{biotype_mapper};
}


# Specify path to write to.
sub write_to_file {
  my ($self,$path) = @_;
  my $fh = IO::File->new($path, 'w');
  $self->filehandle($fh);
}

# General header stuff
sub print_namespaces {
  my $self = shift;
  my $fh = $self->filehandle;
  print $fh name_spaces()."\n";
}

sub print_species_info {
  my $self = shift;
  # create a map of taxon id to species name, we will create some triples for these at the end
  my $fh = $self->filehandle;
  my $meta = $self->meta_adaptor;
  # get the taxon id for this species 
  # Note that a different approach may be required for Ensembl Genomes.
  my $taxon_id = $meta->get_taxonomy_id;
  my $scientific_name = $meta->get_scientific_name;
  my $common_name = $meta->get_common_name;

  # print out global triples about the organism  
  print $fh triple('taxon:'.$taxon_id, 'rdfs:subClassOf', 'obo:OBI_0100026');
  print $fh triple('taxon:'.$taxon_id, 'rdfs:label', qq("$scientific_name"));
  print $fh triple('taxon:'.$taxon_id, 'skos:altLabel', qq("$common_name"));
  print $fh triple('taxon:'.$taxon_id, 'dc:identifier', qq("$taxon_id"));
}

# SO terms often required for dumping RDF
sub getSOOntologyId {
  my ($self,$term) = @_;
  my $ontology_cache = $self->ontology_cache;
  if (exists $self->{$ontology_cache->{$term}}) {
    return $self->{$ontology_cache->{$term}};
  }

  my ($typeterm) = @{ $self->ontology_adaptor->fetch_all_by_name( $term, 'SO' ) };
    
  unless ($typeterm) {
    warn "Can't find SO term for biotype $term\n";
    $self->{$ontology_cache->{$term}} = undef; 
    return;
  }
    
  my $id = $typeterm->accession;
  $self->{$ontology_cache->{$term}} = $id;
  return $id;
}
# Requires a filehandle for the virtuoso file
sub create_virtuoso_file {
  my $self = shift;
  my $fh = shift; # a .graph file, named after the rdf file.
  my $version = Bio::EnsEMBL::ApiVersion->software_version;
  my $taxon_id = $self->meta_adaptor->get_taxonomy_id;

  my $versionGraphUri = "http://rdf.ebi.ac.uk/dataset/ensembl/".$version;
  my $graphUri = $versionGraphUri."/".$taxon_id;
  print $fh $graphUri;
  # make the species graph a subgraph of the version graph, by adding the assertion to the main RDF file.
  my $rdf_fh = $self->filehandle;
  print $rdf_fh triple(u($graphUri), '<http://www.w3.org/2004/03/trix/rdfg-1/subGraphOf>', u($versionGraphUri)); 
}

# Run once before dumping genes
sub print_seq_regions {
  my $self = shift;
  my $slice_list = shift;
  my $fh = $self->filehandle;
  
  my $version = $self->release;
  my $taxon_id = $self->meta_adaptor->get_taxonomy_id;
  my $scientific_name = $self->meta_adaptor->get_scientific_name;
  foreach my $slice ( @$slice_list ) {
    my $region_name = $slice->name();
    my $coord_system = $slice->coord_system();
    my $cs_name = $coord_system->name();
    my $cs_version = $coord_system->version;

    # Generate a version specific portion of a URL that includes the database version, species, assembly version and region name
    # e.g. The URI for human chromosome 1 in assembly GRCh37 would be http://rdf.ebi.ac.uk/resource/ensembl/75/GRCh37/1
    my $version_uri = u( sprintf "%s%s/%s", prefix('ensembl'),$version,$region_name); 
    
    # we also create a non versioned URI that is a superclass e.g. 
    # http://rdf.ebi.ac.uk/resource/ensembl/homo_sapiens/1
    my $non_version_uri = u( sprintf "%s%s/%s", prefix('ensembl'),$taxon_id,$region_name); 
    
    my $reference = $version_uri; # don't need a u($version_uri) because these are keyed off abbreviations
    my $generic = $non_version_uri;
    print $fh triple($reference, 'rdfs:subClassOf', $generic);
    if ($cs_name eq 'chromosome') { 
      print $fh triple($generic, 'rdfs:subClassOf', 'obo:SO_0000340');
    } else {
      print $fh triple($generic, 'rdfs:subClassOf', 'term:'.$cs_name);
      print $fh triple('term:'.$cs_name, 'rdfs:subClassOf', 'term:EnsemblRegion');
    }
    print $fh triple($generic, 'rdfs:label', qq("$scientific_name $cs_name $region_name")); 
    print $fh triple($reference, 'rdfs:label', qq("$scientific_name $cs_name $region_name ($cs_version)"));  
    print $fh triple($reference, 'dc:identifier', qq("$region_name")); 
    print $fh triple($reference, 'term:inEnsemblSchemaNumber', qq("$version"));  
    print $fh triple($reference, 'term:inEnsemblAssembly', qq("$cs_version")); 
  }
  
}

# This method calls recursively down the gene->transcript->translation chain and prints them all
# It can also be used safely with other kinds of features, at least superficially.
# Any specific vocabulary must be added to describe anything other than the entity and its location
sub print_feature {
  my $self = shift;
  my $feature = shift;
  my $feature_uri = shift;
  my $feature_type = shift; # aka table name

  my $fh = $self->filehandle;
  # Translations don't have biotypes. Other features won't either.
  if (exists $feature->{biotype}) {
    my $biotype = $feature->{biotype};

    try { 
      my $so_term;
      if ($feature_type eq 'gene') {$so_term = $self->biotype_mapper->gene_biotype_to_name($biotype) }
      elsif ($feature_type eq 'transcript') {$so_term = $self->biotype_mapper->transcript_biotype_to_name($biotype) }
      else {
        $so_term = $self->getSOOntologyId($biotype);
      }
      print $fh triple(u($feature_uri), 'a', 'obo:'.clean_for_uri($so_term)) if $so_term;
    } catch { 
      if (! exists $self->{ontology_cache}->{$biotype}) { warn sprintf "failed to map biotype %s to SO term\n",$biotype; $self->{ontology_cache}->{$biotype} = undef }
    };
    print $fh triple(u($feature_uri), 'a', 'term:'.clean_for_uri($biotype));
  }
  print $fh triple(u($feature_uri), 'rdfs:label', '"'.$feature->{name}.'"') if defined $feature->{name};
  print $fh triple(u($feature_uri), 'dc:description', '"'.escape($feature->{description}).'"') if defined $feature->{description};
  print $fh taxon_triple(u($feature_uri),$self->meta_adaptor->get_taxonomy_id);

  print $fh triple(u($feature_uri), 'dc:identifier', '"'.$feature->{id}.'"' );

  # Identifiers.org mappings
  $self->identifiers_org_mapping($feature->{id},$feature_uri,'ensembl');
  $self->print_other_accessions($feature,$feature_uri);
  # Describe location in Faldo
  $self->print_faldo_location($feature,$feature_uri) unless $feature_type eq 'translation';

  # Print out synonyms
  for my $synonym ( @{$feature->{synonyms}} ) {
    print $fh triple(u($feature_uri),'skos:altlabel', '"'.escape($synonym).'"' );
  }
  my $provenance;
  $provenance = 'ANNOTATED' if $feature_type eq 'gene';
  $provenance = 'INFERRED_FROM_TRANSCRIPT' if $feature_type eq 'transcript';
  $provenance = 'INFERRED_FROM_TRANSLATION' if $feature_type eq 'translation';

  $self->print_xrefs($feature->{xrefs},$feature_uri,$provenance,$feature_type);
  
  # connect genes to transcripts. Note recursion
  if ($feature_type eq 'gene' && exists $feature->{transcripts}) {
    foreach my $transcript (@{$feature->{transcripts}}) {
      my $transcript_uri = prefix('transcript').$transcript->{id};
      $self->print_feature($transcript,$transcript_uri,'transcript');
      print $fh triple(u($transcript_uri),'obo:SO_transcribed_from',u($feature_uri));
      $self->print_exons($transcript,$transcript_uri);
    }
    if (exists $feature->{homologues} ) {
      foreach my $alt_gene (@{ $feature->{homologues} }) {
        print $fh triple(u($feature_uri), 'sio:SIO_000558', 'ensembl:'.$alt_gene->{stable_id});
      }
    }
  }

  # connect transcripts to translations
  if ($feature_type eq 'transcript' && exists $feature->{translations}) {
    foreach my $translation (@{$feature->{translations}}) {
      my $translation_uri = prefix('protein').$translation->{id};
      $self->print_feature($translation,$translation_uri,'translation');
      print $fh triple(u($feature_uri),'obo:SO_translates_to',u($translation_uri));
      if (exists $translation->{protein_features} && defined $translation->{protein_features}) {
        $self->print_protein_features($translation_uri,$translation->{protein_features});
      }
    }
  }
}

sub print_faldo_location {
  my ($self,$feature,$feature_uri) = @_;
  my $fh = $self->filehandle;

  my $schema_version = $self->release();

  my $region_name = $feature->{seq_region_name};
  my $coord_system = $feature->{coord_system};
  my $cs_name = $coord_system->{name};
  my $cs_version = $coord_system->{version};
  my $prefix = prefix('ensembl');
  unless (defined $region_name && defined $coord_system && defined $cs_name && defined $cs_version) {
    croak ('Cannot print location triple without seq_region_name, coord_system name and version, and a release');
  }
  # LRGs have their own special seq regions... they may not make a lot of sense
  # in the RDF context.
  # The same is true of toplevel contigs in other species.
  my $version_uri;
  if ( defined $cs_version) {
    $version_uri = qq($prefix$schema_version/$cs_name:$cs_version:$region_name);
  }  else {
    $version_uri = qq($prefix$schema_version/$cs_name:$region_name);
  }
  
  my $start = $feature->{start};
  my $end = $feature->{end};
  my $strand = $feature->{strand};
  my $begin = ($strand >= 0) ? $start : $end;
  my $stop = ($strand >= 0) ? $end : $start;
  my $location = sprintf "%s:%s-%s:%s",$version_uri,$start,$end,$strand;
  my $beginUri = sprintf "%s:%s:%s",$version_uri,$begin,$strand;
  my $endUri = "$version_uri:$stop:$strand";
  print $fh triple(u($feature_uri), 'faldo:location', u($location));
  print $fh triple(u($location), 'rdfs:label', qq("$cs_name $region_name:$start-$end:$strand"));
  print $fh triple(u($location), 'rdf:type', 'faldo:Region');
  print $fh triple(u($location), 'faldo:begin', u($beginUri));
  print $fh triple(u($location), 'faldo:end', u($endUri));
  print $fh triple(u($location), 'faldo:reference', u($version_uri));
  print $fh triple(u($beginUri), 'rdf:type', 'faldo:ExactPosition');
  print $fh triple(u($beginUri), 'rdf:type', ($strand >= 0)? 'faldo:ForwardStrandPosition':'faldo:ReverseStrandPosition');

  print $fh triple(u($beginUri), 'faldo:position', $begin);
  print $fh triple(u($beginUri), 'faldo:reference', u($version_uri));

  print $fh triple(u($endUri), 'rdf:type', 'faldo:ExactPosition');
  print $fh triple(u($endUri), 'rdf:type', ($strand >= 0)? 'faldo:ForwardStrandPosition':'faldo:ReverseStrandPosition');

  print $fh triple(u($endUri), 'faldo:position', $stop);
  print $fh triple(u($endUri), 'faldo:reference', u($version_uri));
  
  return $location;
}

sub print_exons {
  my ($self,$transcript,$transcript_uri) = @_;
  my $fh = $self->filehandle;

  return unless exists $transcript->{exons};
  # Assert Exon bag for a given transcript, exons are ordered by rank of the transcript.
  foreach my $exon (@{ $transcript->{exons} }) {
      # exon type of SO exon, both gene and transcript are linked via has part
      print $fh triple('exon:'.$exon->{id},'a','obo:SO_0000147');
      #triple('exon:'.$exon->stable_id,'a','term:exon');
      print $fh triple('exon:'.$exon->{id}, 'rdfs:label', '"'.$exon->{id}.'"');
      print $fh triple('transcript:'.$transcript->{id}, 'obo:SO_has_part', 'exon:'.$exon->{id});
      
      $self->print_feature($exon, prefix('exon').$exon->{id},'exon');
      my $rank = $exon->{rank};
      print $fh triple('transcript:'.$transcript->{id}, 'sio:SIO_000974',  u(prefix('transcript').$transcript->{id}.'#Exon_'.$rank));
      print $fh triple(u(prefix('transcript').$transcript->{id}.'#Exon_'.$rank),  'a', 'sio:SIO_001261');
      print $fh triple(u(prefix('transcript').$transcript->{id}.'#Exon_'.$rank), 'sio:SIO_000628', 'exon:'.$exon->{id});
      print $fh triple(u(prefix('transcript').$transcript->{id}.'#Exon_'.$rank), 'sio:SIO_000300', $rank);
    }
}

# Should be unnecessary once Xref RDF is produced separately from the release database
# Also put associated xrefs through this:
#     my $axN = 0;
# for my $axref (@{$xref->{associated_xrefs}}) {
#   # create a holding triple for each set of annotations
#   my $ax_uri = $idorguri.'_ax_'.(++$axN);
#   print $fh triple(u($idorguri), 'term:annotated', u($ax_uri)); 
#   while(my ($k,$v) = each %$axref) {
#       $k =~ tr/\t /_/;
#       # use the condition directly here
#       # u($ax_uri);
#   }
# }
sub print_xrefs {
  my $self = shift;
  my $xref_list = shift;
  my $feature_uri = shift;
  my $relation = shift;
  my $feature_type = shift;
  return if $feature_type eq 'exon';
  $relation = 'term:'.$relation;
  my $fh = $self->filehandle;

  foreach my $xref (@$xref_list) {
    my $label = $xref->{display_id};
    my $db_name = $xref->{dbname};
    my $id = $xref->{primary_id};
    $id = clean_for_uri($id);
    my $desc = $xref->{description};
    
    # implement the SIO identifier type description see https://github.com/dbcls/bh14/wiki/Identifiers.org-working-document
    # See also xref_config.txt/xref_LOD_mapping.json
    my $id_org_uri = $self->identifiers_org_mapping($id,$feature_uri,$db_name);
    # Next make an "ensembl" style xref. It's a bit of duplication. This might need improving
    my $xref_uri = prefix('ensembl').$db_name.'/'.$id;
    print $fh triple(u($feature_uri), $relation, u($xref_uri));
    print $fh triple(u($xref_uri), 'dc:identifier', qq("$id"));
    if(defined $label && $label ne $id) {
      print $fh triple(u($xref_uri), 'rdfs:label', qq("$label"));
    }
    if ($desc) {
      print $fh triple(u($xref_uri), 'dc:description', '"'.escape($desc).'"');
    }
    # Add any associated xrefs OPTIONAL. Hardly any in Ensembl main databases, generally from eg.
    # Pombase uses them extensively to qualify "ontology xrefs".


  }
}
# For features and xrefs, the identifiers.org way of describing the resource

# (feature/xref)--rdfs:seeAlso->(identifiers.org/db/URI)--a->(identifiers.org/db)
#                                                       \-sio:SIO_000671->()--a->type.identifiers.org/db
#                                                                           \-sio:SIO_000300->"feature_id"
# SIO_000300 = has-value
# SIO_000671 = has-identifier

my %missing_id_mappings = ();
sub identifiers_org_mapping {
  my ($self,$feature_id,$feature_uri,$db) = @_;
  my $fh = $self->filehandle;
  my $id_mapper = $self->ensembl_mapper;
  my $id_org_abbrev = $id_mapper->identifier_org_short($db);
  my $id_org_uri;
  if ($id_org_abbrev) {
    $id_org_uri = prefix('identifiers').$id_org_abbrev.'/'.$feature_id;
    print $fh triple(u($feature_uri), 'rdfs:seeAlso', u( $id_org_uri ));
    print $fh triple(u($id_org_uri), 'a', 'identifiers:'.$id_org_abbrev);
    print $fh triple(u($id_org_uri),'sio:SIO_000671',"[a ident_type:$id_org_abbrev; sio:SIO_000300 \"$feature_id\"]");
    return $id_org_uri;
  } else {
    unless (exists $missing_id_mappings{$db}) {
      $missing_id_mappings{$db} = 1;
      warn "Failed to resolve $db in identifier.org mappings";
    }
  }

}

# Adds INSDC/RefSeq accession links
sub print_other_accessions {
  my ($self,$feature,$feature_uri) = @_;
  my $fh = $self->filehandle;
  if(exists $feature->{seq_region_synonyms} && defined $feature->{seq_region_synonyms}) {
    for my $syn (@{$feature->{seq_region_synonyms}}) {
      my $exdbname = $syn->{db};
      my $id = $syn->{id};
      if(defined $id) {
        my $external_feature;
        if ($exdbname && $exdbname =~/EMBL/i) {
          $external_feature = prefix('identifiers').'insdc/'.$id;
        } elsif($exdbname && $exdbname =~/RefSeq/i) {
          $external_feature = prefix('identifiers').'refseq/'.$id;
        }
        if(defined $external_feature) {
          print $fh triple(u($external_feature), 'dc:identifier', '"'.$id.'"');
          print $fh triple(u($feature_uri), 'sio:equivalentTo', u($external_feature));  
        }
      }
    }
  }
}


my $warned = {};
sub print_protein_features {
  my ($self, $featureIdUri, $protein_features) = @_;
  my $fh = $self->filehandle;
  foreach my $pf (@$protein_features) {
    next unless (defined $pf->{dbname} && defined $pf->{name});
    my $dbname = lc($pf->{dbname});
    if(defined prefix($dbname)) {
      print $fh triple($featureIdUri, 'rdfs:seeAlso', $dbname.':'.$pf->{name});    
    } elsif(!defined $warned->{$dbname}) {
      print "No type found for protein feature from $dbname\n";
      $warned->{dbname} = 1;
    }   
  }
}

1;