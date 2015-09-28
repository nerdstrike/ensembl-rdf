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
use IO::File;


# Required args: species, filehandle, , , xref_mapping_file.json
# override release value from API
sub new {
  my ($caller,@args) = @_;
  my ($ontology_adaptor, $meta_adaptor, $species, $fh, $release,$xref_mapping_file) = @args;
  unless ($release) {
    $release = Bio::EnsEMBL::ApiVersion->software_version;
  }
  my $xref_mapping = Bio::EnsEMBL::RDF::EnsemblToIdentifierMappings->new($xref_mapping_file);
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
  print $fh name_spaces();
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
    warn "Can't find SO term for $term\n";
    $self->{$ontology_cache->{$term}} = undef; 
    return;
  }
    
  my $id = $typeterm->accession;
  $id =~ s/SO:/obo:SO_/;
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
    my $version_uri = qq(ensembl:$version/$cs_name:$cs_version:$region_name); 
    
    # we also create a non versioned URI that is a superclass e.g. 
    # http://rdf.ebi.ac.uk/resource/ensembl/homo_sapiens/1
    my $non_version_uri = qq(ensembl:$taxon_id/$cs_name:$region_name); 
    
    my $reference = u($version_uri);
    my $generic = u($non_version_uri);
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


sub print_feature {
  my $self = shift;
  my $feature = shift;
  my $feature_uri = shift;
  my $feature_type = shift; # aka table name

  my $fh = $self->filehandle;
  my $so_term = $self->getSOOntologyId($feature->{biotype});
   
  print $fh triple($feature_uri, 'a', $so_term);
  print $fh triple($feature_uri, 'a', 'term:'.$feature->{biotype});
  print $fh triple($feature_uri, 'rdfs:label', qq('$feature->name')) if defined $feature->{name};
  print $fh triple($feature_uri, 'dc:description', escape($feature->{description})) if defined $feature->{description};
  print $fh taxon_triple($feature_uri,$self->taxon);

  print $fh triple($feature_uri, 'dc:identifier', '"'.$feature->{id}.'"' );

  # Identifiers.org mappings
  $self->identifiers_org_mapping($feature->{id},$feature_uri,'ensembl');
  
  # Describe location in Faldo
  my $schema_version = $self->release();

  my $region_name = $feature->{seq_region_name};
  my $coord_system = $feature->{coord_system};
  my $cs_name = $coord_system->name;
  my $cs_version = $coord_system->version;

  my $version_uri = qq(ensembl:$schema_version/$cs_name:$cs_version:$region_name);
  my $start = $feature->{start};
  my $end = $feature->{end};
  my $strand = $feature->{strand};
  my $begin = ($strand >= 0) ? $start : $end;
  my $stop = ($strand >= 0) ? $end : $start;
  my $location = u(sprintf "%s:%s-%s:%s",$version_uri,$start,$end,$strand);
  my $beginUri = u(sprintf "%s:%s:%s",$version_uri,$begin,$strand);
  my $endUri = u("$version_uri:$stop:$strand");
  print $fh triple($feature_uri, 'faldo:location', $location);
  print $fh triple($location, 'rdfs:label', qq("$cs_name $region_name:$start-$end:$strand"));
  print $fh triple($location, 'rdf:type', 'faldo:Region');
  print $fh triple($location, 'faldo:begin', $beginUri);
  print $fh triple($location, 'faldo:end', $endUri);
  print $fh triple($location, 'faldo:reference', u($version_uri));
  print $fh triple($beginUri, 'rdf:type', 'faldo:ExactPosition');
  print $fh triple($beginUri, 'rdf:type', ($strand >= 0)? 'faldo:ForwardStrandPosition':'faldo:ReverseStrandPosition');

  print $fh triple($beginUri, 'faldo:position', $begin);
  print $fh triple($beginUri, 'faldo:reference', u($version_uri));

  print $fh triple($endUri, 'rdf:type', 'faldo:ExactPosition');
  print $fh triple($endUri, 'rdf:type', ($strand >= 0)? 'faldo:ForwardStrandPosition':'faldo:ReverseStrandPosition');

  print $fh triple($endUri, 'faldo:position', $stop);
  print $fh triple($endUri, 'faldo:reference', u($version_uri));


  # Print out synonyms
  for my $synonym ( @{$feature->{synonyms}} ) {
    print $fh triple($feature_uri,'skos:altlabel', '"'.escape($synonym).'"' );
  }
  my $provenance;
  $provenance = 'ANNOTATED' if $feature_type eq 'gene';
  $provenance = 'INFERRED_FROM_TRANSCRIPT' if $feature_type eq 'transcript';
  $provenance = 'INFERRED_FROM_TRANSLATION' if $feature_type eq 'translation';

  $self->print_xrefs($feature->{xrefs},$feature_uri,$provenance);
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
  $relation = 'term:'.$relation;
  my $fh = $self->filehandle;

  foreach my $xref (@$xref_list) {
    my $label = $xref->{display_id};
    my $db_name = $xref->{dbname};
    my $id = $xref->{primary_id};
    my $desc = $xref->{description};
    
    # implement the SIO identifier type description see https://github.com/dbcls/bh14/wiki/Identifiers.org-working-document
    # See also xref_config.txt/xref_LOD_mapping.json
    $self->identifiers_org_mapping($id,$feature_uri,$db_name);

    print $fh triple($feature_uri, $relation, u($xref));
    print $fh triples(u($xref), 'dc:identifier', qq("$id"));
    if(defined $label && $label ne $id) {
      print $fh triple(u($xref), 'rdfs:label', qq("$label"));
    }
    if ($desc) {
      print $fh triple(u($xref), 'dc:description', '"'.escape($desc).'"');
    }


  }
}
# For features and xrefs, the identifiers.org way of describing the resource

# (feature/xref)--rdfs:seeAlso->(identifiers.org/db/URI)--a->(identifiers.org/db)
#                                                       \-sio:SIO_000671->()--a->type.identifiers.org/db
#                                                                           \-sio:SIO_000300->"feature_id"
# SIO_000300 = has-value
# SIO_000671 = has-identifier
sub identifiers_org_mapping {
  my ($self,$feature_id,$feature_uri,$db) = @_;
  my $fh = $self->filehandle;
  my $id_mapper = $self->mappings;
  my $id_org_abbrev = $id_mapper->identifier_org_short($db);

  my $id_org_uri = 'identifiers:'.$id_org_abbrev.'/'.$feature_id;
  print $fh triple($feature_uri, 'rdfs:seeAlso', $id_org_uri);
  if ($id_org_abbrev) {
    print $fh triple($id_org_uri, 'a', 'identifiers:'.$id_org_abbrev);
    print $fh triple($id_org_uri,'sio:SIO_000671',"[a ident_type:$id_org_abbrev; sio:SIO_000300 \"$feature_id\"]");
  }

}

my $warned = {};
sub print_protein_features {
  my ($self, $featureIdUri, $protein_feature) = @_;
  my $fh = $self->filehandle;
  return unless (defined $protein_feature->{dbname} && defined $protein_feature->{name});

  my $dbname = lc($protein_feature->{dbname});
  
  if(defined prefix($dbname)) {
    print $fh triple($featureIdUri, 'rdfs:seeAlso', $dbname.':'.$protein_feature->{name});    
  } elsif(!defined $warned->{$dbname}) {
    # $self->log->warn("No type found for protein feature from $dbname");
    $warned->{dbname} = 1;
  }
  return;
}

1;