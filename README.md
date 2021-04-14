# :microbe: `metaGEM` :gem:

> A workflow to predict metabolic interactions within microbial communities directly from metagenomic data.

![metawrapfigs_v2 002](https://user-images.githubusercontent.com/35606471/103545679-ceb71580-4e99-11eb-9862-084115121980.jpeg)

`metaGEM` integrates an array of existing bioinformatics and metabolic modeling tools using Snakemake, for the purpose of predicting metabolic interactions within bacterial communities of microbiomes. From whole metagenome shotgun datasets, metagenome assembled genomes (MAGs) are reconstructed, which are then converted into genome-scale metabolic models (GEMs) for *in silico* simulations of cross feeding interactions within sample based communities. Additional outputs include abundance estimates, taxonomic assignment, growth rate estimation, pangenome analysis, and eukaryotic MAG identification.

## :bulb: Quickstart

Clone this repository to your HPC or local computer and run the `env_setup.sh` script:

```
git clone https://github.com/franciscozorrilla/metaGEM.git # Download metaGEM repo
cd metaGEM # Move into metaGEM directory
rm -r .git # Remove ~250 Mb of uneeded git history files
bash env_setup.sh # Run automated setup script
```

This script will set up 3 conda environments, `metagem`, `metawrap`, and `prokkaroary`, which will be activated as required by Snakemake jobs.

Please see the [setup page](https://github.com/franciscozorrilla/metaGEM/wiki/Quickstart) in the wiki for further installation instructions.

## :school_satchel: Tutorial

`metaGEM` can even be used to explore your own gut microbiome sequencing data from at-home-test-kit services such as [unseen bio](https://unseenbio.com/). The [following tutorial](https://github.com/franciscozorrilla/unseenbio_metaGEM) showcases the `metaGEM` workflow on two unseenbio samples.

## :book: Wiki

Please check out the [wiki](https://github.com/franciscozorrilla/metaGEM/wiki) for additional usage tips, frequently asked questions, and implementation details. 

## :wrench: Workflow

### Core

1. Quality filter reads with [fastp](https://github.com/OpenGene/fastp)
2. Assembly with [megahit](https://github.com/voutcn/megahit)
3. Draft bin sets with [CONCOCT](https://github.com/BinPro/CONCOCT), [MaxBin2](https://sourceforge.net/projects/maxbin2/), and [MetaBAT2](https://sourceforge.net/projects/maxbin2/)
4. Refine & reassemble bins with [metaWRAP](https://github.com/bxlab/metaWRAP)
5. Taxonomic assignment with [GTDB-tk](https://github.com/Ecogenomics/GTDBTk)
6. Relative abundances with [bwa](https://github.com/lh3/bwa) and [samtools](https://github.com/samtools/samtools)
7. Reconstruct & evaluate genome-scale metabolic models with [CarveMe](https://github.com/cdanielmachado/carveme) and [memote](https://github.com/opencobra/memote)
8. Species metabolic coupling analysis with [SMETANA](https://github.com/cdanielmachado/smetana)

### Bonus

9. Growth rate estimation with [GRiD](https://github.com/ohlab/GRiD), [SMEG](https://github.com/ohlab/SMEG) or [CoPTR](https://github.com/tyjo/coptr)
10. Pangenome analysis with [roary](https://github.com/sanger-pathogens/Roary)
11. Eukaryotic draft bins with [EukRep](https://github.com/patrickwest/EukRep) and [EukCC](https://github.com/Finn-Lab/EukCC)

## :construction: Active Development

Are you sad that your favorite binner didn't make it into the `metaGEM` workflow? Have you developed a new bioinformatics tool that you would like to see incorporated into `metaGEM`? Want alternative tools for certain tasks or even new additional features? We want to hear from you! 

If you want to see any new additional or alternative tools incorporated into the `metaGEM` workflow please do not hesitate to raise an issue or create a pull request. Snakemake allows workflows to be very flexible, and adding new rules is as easy as filling out the following template and adding it to the Snakefile:

```
rule package-name:
    input:
        rules.rulename.output
    output:
        f'{config["path"]["root"]}/{config["folder"]["X"]}/{{IDs}}/output.file'
    message:
        """
        Helpful and descriptive message detailing goal of this rule/package.
        """
    shell:
        """
        # Well documented command line instructions go here
        
        # Load conda environment 
        set +u;source activate {config[envs][package]};set -u;

        # Run tool
        package-name -i {input} -o {output}
        """
```

## :paperclip: Publications

The `metaGEM` workflow has been used in some capacity in the following publications:

```
Plastic-degrading potential across the global microbiome correlates with recent pollution trends
Jan Zrimec, Mariia Kokina, Sara Jonasson, Francisco Zorrilla, Aleksej Zelezniak
bioRxiv 2020.12.13.422558; doi: https://doi.org/10.1101/2020.12.13.422558 
```

## :heavy_check_mark: Please cite

```
metaGEM: reconstruction of genome scale metabolic models directly from metagenomes
Francisco Zorrilla, Kiran R. Patil, Aleksej Zelezniak
bioRxiv 2020.12.31.424982; doi: https://doi.org/10.1101/2020.12.31.424982 
```

## 📲 Contact

Feel free to reach out with any comments, concerns, or discussions regarding `metaGEM`.

* Twitter: [@metagenomez](https://twitter.com/metagenomez)
* LinkedIn: [@fzorrilla94](https://www.linkedin.com/in/fzorrilla94/)
* Email: fz274@cam.ac.uk
