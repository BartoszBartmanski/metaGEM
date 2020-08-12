configfile: "config.yaml"

import os
import glob

def get_ids_from_path_pattern(path_pattern):
    ids = sorted([os.path.basename(os.path.splitext(val)[0])
                  for val in (glob.glob(path_pattern))])
    return ids

# Make sure that final_bins/ folder contains all bins in single folder for binIDs
gemIDs = get_ids_from_path_pattern('GEMs/*.xml')
binIDs = get_ids_from_path_pattern('protein_bins/*.faa')
IDs = get_ids_from_path_pattern('qfiltered/*')
speciesIDs = get_ids_from_path_pattern('pangenome/speciesBinIDs/*.txt')
DATA_READS_1 = f'{config["path"]["root"]}/{config["folder"]["data"]}/{{IDs}}/{{IDs}}_1.fastq.gz'
DATA_READS_2 = f'{config["path"]["root"]}/{config["folder"]["data"]}/{{IDs}}/{{IDs}}_2.fastq.gz'
focal = get_ids_from_path_pattern('dataset/*')

rule all:
    input:
        expand(f'{config["path"]["root"]}/{config["folder"]["pangenome"]}/roary/{{speciesIDs}}/', speciesIDs=speciesIDs)
    message:
        """
        WARNING: Be very careful when adding/removing any lines above this message.
        The metaBAGpipes.sh parser is presently hardcoded to edit line 22 of this Snakefile to expand target rules accordingly,
        therefore adding/removing any lines before this message will likely result in parser malfunction.
        """
    shell:
        """
        echo {input}
        """

rule createFolders:
    input:
        config["path"]["root"]
    message:
        """
        Very simple rule to check that the metaBAGpipes.sh parser, Snakefile, and config.yaml file are set up correctly. 
        Generates folders from config.yaml config file, not strictly necessary to run this rule.
        """
    shell:
        """
        cd {input}
        echo -e "Setting up result folders in the following work directory: $(echo {input}) \n"

        # Generate folders.txt by extracting folder names from config.yaml file
        paste config.yaml |cut -d':' -f2|tail -n +4|head -n 21|sed '/^$/d' > folders.txt # NOTE: hardcoded number (21) for folder names, increase number as new folders are introduced.
        
        while read line;do 
            echo "Creating $line folder ... "
            mkdir -p $line;
        done < folders.txt
        
        echo -e "\nDone creating folders. \n"

        rm folders.txt
        """


rule downloadToy:
    input:
        f'{config["path"]["root"]}/{config["folder"]["scripts"]}/{config["scripts"]["toy"]}'
    message:
        """
        Downloads toy dataset into config.yaml data folder and organizes into sample-specific sub-folders.
        Requires download_toydata.txt to be present in scripts folder.
        Modify this rule to download a real dataset by replacing the links in the download_toydata.txt file with links to files from your dataset of intertest.
        """
    shell:
        """
        cd {config[path][root]}/{config[folder][data]}

        # Download each link in download_toydata.txt
        echo -e "\nBegin downloading toy dataset ... \n"
        while read line;do 
            wget $line;
        done < {input}
        echo -e "\nDone donwloading dataset.\n"
        
        # Rename downloaded files, this is only necessary for toy dataset (will cause error if used for real dataset)
        echo -ne "\nRenaming downloaded files ... "
        for file in *;do 
            mv $file ./$(echo $file|sed 's/?download=1//g');
        done
        echo -e " done. \n"

        # Organize data into sample specific sub-folders

        echo -ne "\nGenerating list of unique sample IDs ... "
        for file in *.gz; do 
            echo $file; 
        done | sed 's/_.*$//g' | sed 's/.fastq.gz//g' | uniq > ID_samples.txt
        echo -e " done.\n $(less ID_samples.txt|wc -l) samples identified.\n"

        echo -ne "\nOrganizing downloaded files into sample specific sub-folders ... "
        while read line; do 
            mkdir -p $line; 
            mv $line*.gz $line; 
        done < ID_samples.txt
        echo -e " done. \n"
        
        rm ID_samples.txt
        """


rule organizeData:
    input:
        f'{config["path"]["root"]}/{config["folder"]["data"]}'
    message:
        """
        Sorts paired end raw reads into sample specific sub folders within the dataset folder specified in the config.yaml file.
        Assumes all samples are present in abovementioned dataset folder.
        
        Note: This rule is meant to be run on real datasets. 
        Do not run for toy dataset, as downloadToy rule above sorts the downloaded data already.

        Assumes file names have format: SAMPLEID_1|2.fastq.gz, e.g. ERR599026_2.fastq.gz
        """
    shell:
        """
        cd {input}
    
        echo -ne "\nGenerating list of unique sample IDs ... "

        # Create list of unique sample IDs
        for file in *.gz; do 
            echo $file; 
        done | sed 's/_.*$//g' | sed 's/.fastq.gz//g' | uniq > ID_samples.txt

        echo -e " done.\n $(less ID_samples.txt|wc -l) samples identified.\n"

        # Create folder and move corresponding files for each sample

        echo -ne "\nOrganizing dataset into sample specific sub-folders ... "
        while read line; do 
            mkdir -p $line; 
            mv $line*.gz $line; 
        done < ID_samples.txt
        echo -e " done. \n"
        
        rm ID_samples.txt
        """

rule qfilter:
    input:
        R1 = DATA_READS_1,
        R2 = DATA_READS_2
    output:
        R1 = f'{config["path"]["root"]}/{config["folder"]["qfiltered"]}/{{IDs}}/{{IDs}}_1.fastq.gz', 
        R2 = f'{config["path"]["root"]}/{config["folder"]["qfiltered"]}/{{IDs}}/{{IDs}}_2.fastq.gz' 
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        mkdir -p $(dirname {output.R1})

        fastp --thread {config[cores][fastp]} \
            -i {input.R1} \
            -I {input.R2} \
            -o {output.R1} \
            -O {output.R2} \
            -j $(dirname {output.R1})/$(echo $(basename $(dirname {output.R1}))).json \
            -h $(dirname {output.R1})/$(echo $(basename $(dirname {output.R1}))).html

        """


rule qfilterVis:
    input: 
        f'{config["path"]["root"]}/{config["folder"]["qfiltered"]}'
    output: 
        text = f'{config["path"]["root"]}/{config["folder"]["stats"]}/qfilter.stats',
        plot = f'{config["path"]["root"]}/{config["folder"]["stats"]}/qfilterVis.pdf'
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        mkdir -p $(dirname {output.text})
        cd {input}

        echo -e "\nGenerating quality filtering results file qfilter.stats: ... "
        for folder in */;do
            for file in $folder*json;do
                ID=$(echo $file|sed 's|/.*$||g')
                readsBF=$(head -n 25 $file|grep total_reads|cut -d ':' -f2|sed 's/,//g'|head -n 1)
                readsAF=$(head -n 25 $file|grep total_reads|cut -d ':' -f2|sed 's/,//g'|tail -n 1)
                basesBF=$(head -n 25 $file|grep total_bases|cut -d ':' -f2|sed 's/,//g'|head -n 1)
                basesAF=$(head -n 25 $file|grep total_bases|cut -d ':' -f2|sed 's/,//g'|tail -n 1)
                q20BF=$(head -n 25 $file|grep q20_rate|cut -d ':' -f2|sed 's/,//g'|head -n 1)
                q20AF=$(head -n 25 $file|grep q20_rate|cut -d ':' -f2|sed 's/,//g'|tail -n 1)
                q30BF=$(head -n 25 $file|grep q30_rate|cut -d ':' -f2|sed 's/,//g'|head -n 1)
                q30AF=$(head -n 25 $file|grep q30_rate|cut -d ':' -f2|sed 's/,//g'|tail -n 1)
                percent=$(awk -v RBF="$readsBF" -v RAF="$readsAF" 'BEGIN{{print RAF/RBF}}' )
                echo "$ID $readsBF $readsAF $basesBF $basesAF $percent $q20BF $q20AF $q30BF $q30AF" >> qfilter.stats
                echo "Sample $ID retained $percent * 100 % of reads ... "
            done
        done

        echo "Done summarizing quality filtering results ... \nMoving to /stats/ folder and running plotting script ... "
        mv qfilter.stats {config[path][root]}/{config[folder][stats]}
        cd {config[path][root]}/{config[folder][stats]}

        Rscript {config[path][root]}/{config[folder][scripts]}/{config[scripts][qfilterVis]}
        echo "Done. "
        rm Rplots.pdf
        """


rule megahit:
    input:
        R1 = rules.qfilter.output.R1, 
        R2 = rules.qfilter.output.R2
    output:
        f'{config["path"]["root"]}/{config["folder"]["assemblies"]}/{{IDs}}/contigs.fasta.gz'
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.megahit.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        cd $SCRATCHDIR

        echo -n "Copying qfiltered reads to $SCRATCHDIR ... "
        cp {input.R1} {input.R2} $SCRATCHDIR
        echo "done. "

        echo -n "Running megahit ... "
        megahit -t {config[cores][megahit]} \
            --presets {config[params][assemblyPreset]} \
            --verbose \
            --min-contig-len {config[params][assemblyMin]} \
            -1 $(basename {input.R1}) \
            -2 $(basename {input.R2}) \
            -o tmp;
        echo "done. "

        echo "Renaming assembly ... "
        mv tmp/final.contigs.fa contigs.fasta
        
        echo "Fixing contig header names: replacing spaces with hyphens ... "
        sed -i 's/ /-/g' contigs.fasta

        echo "Zipping and moving assembly ... "
        gzip contigs.fasta
        mkdir -p $(dirname {output})
        mv contigs.fasta.gz $(dirname {output})
        echo "Done. "
        """

rule megahitCoassembly:
    input:
        R1 = f'/scratch/zorrilla/soil/coassembly/data/{{borkSoil}}/R1', 
        R2 = f'/scratch/zorrilla/soil/coassembly/data/{{borkSoil}}/R2'
    output:
        f'{config["path"]["root"]}/coassembly/coassemblies/{{borkSoil}}/contigs.fasta.gz'
    benchmark:
        f'{config["path"]["root"]}/benchmarks/coassembly.{{borkSoil}}.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        cd $SCRATCHDIR

        echo -n "Copying qfiltered reads to $SCRATCHDIR ... "
        cp -r {input.R1} {input.R2} $SCRATCHDIR
        echo "done. "

        R1=$(ls R1/|tr '\n' ','|sed 's/,$//g')
        R2=$(ls R2/|tr '\n' ','|sed 's/,$//g')

        mv R1/* .
        mv R2/* .

        echo -n "Running megahit ... "
        megahit -t {config[cores][megahit]} \
            --presets {config[params][assemblyPreset]} \
            --min-contig-len {config[params][assemblyMin]}\
            --verbose \
            -1 $R1 \
            -2 $R2 \
            -o tmp;
        echo "done. "

        echo "Renaming assembly ... "
        mv tmp/final.contigs.fa contigs.fasta
        
        echo "Fixing contig header names: replacing spaces with hyphens ... "
        sed -i 's/ /-/g' contigs.fasta

        echo "Zipping and moving assembly ... "
        gzip contigs.fasta
        mkdir -p $(dirname {output})
        mv contigs.fasta.gz $(dirname {output})
        echo "Done. "
        """


rule assemblyVis:
    input: 
        f'{config["path"]["root"]}/{config["folder"]["assemblies"]}'
    output: 
        text = f'{config["path"]["root"]}/{config["folder"]["stats"]}/assembly.stats',
        plot = f'{config["path"]["root"]}/{config["folder"]["stats"]}/assemblyVis.pdf',
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        mkdir -p $(dirname {output.text})
        cd {input}
    
        echo -e "\nGenerating assembly results file assembly.stats: ... "

        while read assembly;do
            ID=$(echo $(basename $(dirname $assembly)))
            #check if assembly file is empty
            check=$(less $assembly|wc -l)
            if [ $check -eq 0 ]
            then
                N=0
                L=0
            else
                N=$(less $assembly|grep -c ">");
                L=$(less $assembly|grep ">"|cut -d '-' -f4|sed 's/len=//'|awk '{{sum+=$1}}END{{print sum}}');
            fi
            echo $ID $N $L >> assembly.stats;
            echo -e "Sample $ID has a total of $L bp across $N contigs ... "
        done< <(find {input} -name "*.gz")

        echo "Done summarizing assembly results ... \nMoving to /stats/ folder and running plotting script ... "
        #mv assembly.stats {config[path][root]}/{config[folder][stats]}
        cd {config[path][root]}/{config[folder][stats]}

        #Rscript {config[path][root]}/{config[folder][scripts]}/{config[scripts][assemblyVis]}
        echo "Done. "
        #rm Rplots.pdf
        """

rule crossMap:  
    input:
        contigs = rules.megahit.output,
        reads = f'{config["path"]["root"]}/{config["folder"]["qfiltered"]}'
    output:
        #concoct = directory(f'{config["path"]["root"]}/{config["folder"]["concoct"]}/{{IDs}}/cov'),
        #metabat = directory(f'{config["path"]["root"]}/{config["folder"]["metabat"]}/{{IDs}}/cov'),
        #maxbin = directory(f'{config["path"]["root"]}/{config["folder"]["maxbin"]}/{{IDs}}/cov')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.crossMap.benchmark.txt'
    message:
        """
        Use this approach to provide all 3 binning tools with cross-sample coverage information.
        Will likely provide superior binning results, but may no be feasible for datasets with 
        many large samples such as the tara oceans dataset. 
        """
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        cd $SCRATCHDIR
        cp {input.contigs} .

        mkdir -p {output.concoct}
        mkdir -p {output.metabat}
        mkdir -p {output.maxbin}

        # Define the focal sample ID, fsample: 
        # The one sample's assembly that all other samples' read will be mapped against in a for loop
        fsampleID=$(echo $(basename $(dirname {input.contigs})))
        echo -e "\nFocal sample: $fsampleID ... "

        echo "Renaming and unzipping assembly ... "
        mv $(basename {input.contigs}) $(echo $fsampleID|sed 's/$/.fa.gz/g')
        gunzip $(echo $fsampleID|sed 's/$/.fa.gz/g')

        echo -e "\nIndexing assembly ... "
        bwa index $fsampleID.fa
        
        for folder in {input.reads}/*;do 

                id=$(basename $folder)

                echo -e "\nCopying sample $id to be mapped against the focal sample $fsampleID ..."
                cp $folder/*.gz .
                
                # Maybe I should be piping the lines below to reduce I/O ?

                echo -e "\nMapping sample to assembly ... "
                bwa mem -t {config[cores][crossMap]} $fsampleID.fa *.fastq.gz > $id.sam
                
                echo -e "\nConverting SAM to BAM with samtools view ... " 
                samtools view -@ {config[cores][crossMap]} -Sb $id.sam > $id.bam

                echo -e "\nSorting BAM file with samtools sort ... " 
                samtools sort -@ {config[cores][crossMap]} -o $id.sort $id.bam

                echo -e "\nRunning jgi_summarize_bam_contig_depths script to generate contig abundance/depth file for maxbin2 input ... "
                jgi_summarize_bam_contig_depths --outputDepth $id.depth $id.sort

                echo -e "\nMoving depth file to sample $fsampleID maxbin2 folder ... "
                mv $id.depth {output.maxbin}

                echo -e "\nIndexing sorted BAM file with samtools index for CONCOCT input table generation ... " 
                samtools index $id.sort

                echo -e "\nRemoving temporary files ... "
                rm *.fastq.gz *.sam *.bam

        done
        
        nSamples=$(ls {input.reads}|wc -l)
        echo -e "\nDone mapping focal sample $fsampleID agains $nSamples samples in dataset folder."

        echo -e "\nRunning jgi_summarize_bam_contig_depths for all sorted bam files to generate metabat2 input ... "
        jgi_summarize_bam_contig_depths --outputDepth $id.all.depth *.sort

        echo -e "\nMoving input file $id.all.depth to $fsampleID metabat2 folder... "
        mv $id.all.depth {output.metabat}

        echo -e "Done. \nCutting up contigs to 10kbp chunks (default), not to be used for mapping!"
        cut_up_fasta.py -c {config[params][cutfasta]} -o 0 -m $fsampleID.fa -b assembly_c10k.bed > assembly_c10k.fa

        echo -e "\nSummarizing sorted and indexed BAM files with concoct_coverage_table.py to generate CONCOCT input table ... " 
        concoct_coverage_table.py assembly_c10k.bed *.sort > coverage_table.tsv

        echo -e "\nMoving CONCOCT input table to $fsampleID concoct folder"
        mv coverage_table.tsv {output.concoct}

        """


rule crossMap2:  
    input:
        contigs = f'{config["path"]["root"]}/{config["folder"]["assemblies"]}/{{focal}}/contigs.fasta.gz',
        R1 = rules.qfilter.output.R1,
        R2 = rules.qfilter.output.R2
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["crossMap"]}/{{focal}}/{{IDs}}')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{focal}}.{{IDs}}.crossMap.benchmark.txt'
    message:
        """
        This rule is an alternative implementation of the rule crossMap.
        Instead of taking each focal sample as a job and cross mapping in series using a for loop,
        here the cross mapping is done completely in parallel. 
        This implementation is not recommended, as it wastefully recreates a bwa index for each mapping
        operation. Use crossMap for smaller datasets or crossMap3 for larger datasets.
        """
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        cd $SCRATCHDIR

        echo -e "\nCopying assembly {input.contigs} and reads {input.R1} {input.R2} to $SCRATCHDIR"
        cp {input.contigs} {input.R1} {input.R2} .

        mkdir -p {output}

        # Define the focal sample ID, fsample: 
        # The one sample's assembly that reads will be mapped against
        fsampleID=$(echo $(basename $(dirname {input.contigs})))
        echo -e "\nFocal sample: $fsampleID ... "

        echo "Renaming and unzipping assembly ... "
        mv $(basename {input.contigs}) $(echo $fsampleID|sed 's/$/.fa.gz/g')
        gunzip $(echo $fsampleID|sed 's/$/.fa.gz/g')

        echo -e "\nIndexing assembly ... "
        bwa index $fsampleID.fa

        id=$(basename {output})
        echo -e "\nMapping reads from sample $id against assembly of focal sample $fsampleID ..."
        bwa mem -t {config[cores][crossMap]} $fsampleID.fa *.fastq.gz > $id.sam

        echo -e "\nDeleting no-longer-needed fastq files ... "
        rm *.gz
                
        echo -e "\nConverting SAM to BAM with samtools view ... " 
        samtools view -@ {config[cores][crossMap]} -Sb $id.sam > $id.bam

        echo -e "\nDeleting no-longer-needed sam file ... "
        rm $id.sam

        echo -e "\nSorting BAM file with samtools sort ... " 
        samtools sort -@ {config[cores][crossMap]} -o $id.sort $id.bam

        echo -e "\nDeleting no-longer-needed bam file ... "
        rm $id.bam

        echo -e "\nIndexing sorted BAM file with samtools index for CONCOCT input table generation ... " 
        samtools index $id.sort

        echo -e "\nCutting up assembly contigs >= 20kbp into 10kbp chunks and creating bedfile ... "
        cut_up_fasta.py $fsampleID.fa -c 10000 -o 0 --merge_last -b contigs_10K.bed > contigs_10K.fa

        echo -e "\nGenerating CONCOCT individual/intermediate coverage table ... "
        concoct_coverage_table.py contigs_10K.bed *.sort > ${{fsampleID}}_${{id}}_individual.tsv

        echo -e "\nCompressing CONCOCT coverage table ... "
        gzip ${{fsampleID}}_${{id}}_individual.tsv

        echo -e "\nRunning jgi_summarize_bam_contig_depths script to generate contig abundance/depth file for maxbin2 input ... "
        jgi_summarize_bam_contig_depths --outputDepth ${{fsampleID}}_${{id}}_individual.depth $id.sort

        echo -e "\nCompressing maxbin2/metabat2 depth file ... "
        gzip ${{fsampleID}}_${{id}}_individual.depth

        echo -e "\nMoving relevant files to {output}"
        mv *.gz {output}

        """

rule gatherCrossMap2: 
    input:
        expand(f'{config["path"]["root"]}/{config["folder"]["crossMap"]}/{{focal}}/{{IDs}}', focal = focal , IDs = IDs)
    shell:
        """
        echo idk
        """

rule kallistoIndex:
    input:
        f'{config["path"]["root"]}/{config["folder"]["assemblies"]}/{{focal}}/contigs.fasta.gz'
    output:
        f'{config["path"]["root"]}/kallistoIndex/{{focal}}/index.kaix'
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{focal}}.crossMap3.benchmark.txt'
    message:
        """
        Needed for the crossMap3 implementation, which uses kalliso for fast mapping instead of bwa.
        """
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        mkdir -p $(dirname {output})
        cd $SCRATCHDIR        

        sampleID=$(echo $(basename $(dirname {input})))
        echo -e "\nCopying and unzipping sample $sampleID assembly ... "
        cp {input} .
        mv $(basename {input}) $(echo $sampleID|sed 's/$/.fa.gz/g')
        gunzip $(echo $sampleID|sed 's/$/.fa.gz/g')

        echo -e "\nCutting up assembly contigs >= 20kbp into 10kbp chunks ... "
        cut_up_fasta.py $sampleID.fa -c 10000 -o 0 --merge_last > contigs_10K.fa

        echo -e "\nCreating kallisto index ... "
        kallisto index contigs_10K.fa -i index.kaix

        mv index.kaix $(dirname {output})
        """


rule crossMap3:  
    input:
        index = rules.kallistoIndex.output,
        R1 = rules.qfilter.output.R1,
        R2 = rules.qfilter.output.R2
    output:
        directory(f'{config["path"]["root"]}/kallisto/{{focal}}/{{IDs}}')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{focal}}.{{IDs}}.crossMap3.benchmark.txt'
    message:
        """
        This rule is an alternative implementation of crossMap/crossMap2, using kallisto 
        instead of bwa for mapping operations. This implementation is recommended for
        large datasets.
        """
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        cd $SCRATCHDIR

        echo -e "\nCopying assembly index {input.index} and reads {input.R1} {input.R2} to $SCRATCHDIR"
        cp {input.index} {input.R1} {input.R2} .

        mkdir -p {output}

        echo -e "\nRunning kallisto ... "
        kallisto quant --threads {config[cores][crossMap]} --plaintext -i index.kaix -o . $(basename {input.R1}) $(basename {input.R2})
        
        echo -e "\nZipping abundance file ... "
        gzip abundance.tsv

        mv abundance.tsv.gz {output}
        """

rule gatherCrossMap3: 
    input:
        expand(f'{config["path"]["root"]}/kallisto/{{focal}}/{{IDs}}', focal = focal , IDs = IDs)
    shell:
        """
        echo idk
        """

rule kallisto2concoctTable: 
    input:
        f'{config["path"]["root"]}/kallisto/{{focal}}/'
    output: 
        f'{config["path"]["root"]}/concoct_input/{{focal}}_concoct_inputtableR.tsv' 
    message:
        """
        This rule is necessary for the crossMap3 implementation subworkflow.
        It summarizes the individual concoct input tables for a given focal sample.
        """
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        mkdir -p $(dirname {output})
        python {config[path][root]}/{config[folder][scripts]}/{config[scripts][kallisto2concoct]} \
            --samplenames <(for s in {input}*; do echo $s|sed 's|^.*/||'; done) \
            $(find {input} -name "*.gz") > {output}
    
        """

rule concoct:
    input:
        table = f'{config["path"]["root"]}/{config["folder"]["concoct"]}/{{IDs}}/cov/coverage_table.tsv',
        contigs = rules.megahit.output
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["concoct"]}/{{IDs}}/{{IDs}}.concoct-bins')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.concoct.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        mkdir -p $(dirname $(dirname {output}))
        cd $SCRATCHDIR
        cp {input.contigs} {input.table} $SCRATCHDIR

        echo "Unzipping assembly ... "
        gunzip $(basename {input.contigs})

        echo -e "Done. \nCutting up contigs (default 10kbp chunks) ... "
        cut_up_fasta.py -c {config[params][cutfasta]} -o 0 -m $(echo $(basename {input.contigs})|sed 's/.gz//') > assembly_c10k.fa
        
        echo -e "\nRunning CONCOCT ... "
        concoct --coverage_file $(basename {input.table}) \
            --composition_file assembly_c10k.fa \
            -b $(basename $(dirname {output})) \
            -t {config[cores][concoct]} \
            -c {config[params][concoct]}
            
        echo -e "\nMerging clustering results into original contigs ... "
        merge_cutup_clustering.py $(basename $(dirname {output}))_clustering_gt1000.csv > $(basename $(dirname {output}))_clustering_merged.csv
        
        echo -e "\nExtracting bins ... "
        mkdir -p $(basename {output})
        extract_fasta_bins.py $(echo $(basename {input.contigs})|sed 's/.gz//') $(basename $(dirname {output}))_clustering_merged.csv --output_path $(basename {output})
        
        mkdir -p $(dirname {output})
        mv $(basename {output}) *.txt *.csv $(dirname {output})
        """


rule metabat:
    input:
        assembly = rules.megahit.output,
        R1 = rules.qfilter.output.R1,
        R2 = rules.qfilter.output.R2
    output:
        #directory(f'{config["path"]["root"]}/{config["folder"]["metabat"]}/{{IDs}}/{{IDs}}.metabat-bins')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.metabat.benchmark.txt'
    message:
        """
        Implementation of metabat where only coverage information from the focal sample is used
        for binning. Use with the crossMap3 subworkflow, where cross sample coverage information
        is only used by CONCOCT.
        """
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        cp {input.assembly} {input.R1} {input.R2} $SCRATCHDIR
        mkdir -p $(dirname {output})
        cd $SCRATCHDIR

        fsampleID=$(echo $(basename $(dirname {input.assembly})))
        echo -e "\nFocal sample: $fsampleID ... "

        echo "Renaming and unzipping assembly ... "
        mv $(basename {input.assembly}) $(echo $fsampleID|sed 's/$/.fa.gz/g')
        gunzip $(echo $fsampleID|sed 's/$/.fa.gz/g')

        echo -e "\nIndexing assembly ... "
        bwa index $fsampleID.fa

        id=$(basename {output})
        echo -e "\nMapping reads from sample against assembly $fsampleID ..."
        bwa mem -t {config[cores][metabat]} $fsampleID.fa *.fastq.gz > $id.sam

        echo -e "\nDeleting no-longer-needed fastq files ... "
        rm *.gz
                
        echo -e "\nConverting SAM to BAM with samtools view ... " 
        samtools view -@ {config[cores][metabat]} -Sb $id.sam > $id.bam

        echo -e "\nDeleting no-longer-needed sam file ... "
        rm $id.sam

        echo -e "\nSorting BAM file with samtools sort ... " 
        samtools sort -@ {config[cores][metabat]} -o $id.sort $id.bam

        echo -e "\nDeleting no-longer-needed bam file ... "
        rm $id.bam

        echo -e "\nRunning metabat2 ... "
        metabat2 -i $fsampleID.fa $id.sort -s \
            {config[params][metabatMin]} \
            -v --seed {config[params][seed]} \
            -t 0 -m {config[params][minBin]} \
            -o $(basename $(dirname {output}))

        rm $fsampleID.fa

        mkdir -p {output}
        mv *.fa {output}
        """

rule metabatCross:
    input:
        assembly = rules.megahit.output,
        depth = f'{config["path"]["root"]}/{config["folder"]["metabat"]}/{{IDs}}/cov'
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["metabat"]}/{{IDs}}/{{IDs}}.metabat-bins')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.metabat.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        cp {input.assembly} {input.depth}/*.all.depth $SCRATCHDIR
        mkdir -p $(dirname {output})
        cd $SCRATCHDIR
        gunzip $(basename {input.assembly})
        echo -e "\nRunning metabat2 ... "
        metabat2 -i contigs.fasta -a *.all.depth -s {config[params][metabatMin]} -v --seed {config[params][seed]} -t 0 -m {config[params][minBin]} -o $(basename $(dirname {output}))
        mkdir -p {output}
        mv *.fa {output}
        """


rule maxbin:
    input:
        assembly = rules.megahit.output,
        R1 = rules.qfilter.output.R1,
        R2 = rules.qfilter.output.R2
    output:
        #directory(f'{config["path"]["root"]}/{config["folder"]["maxbin"]}/{{IDs}}/{{IDs}}.maxbin-bins')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.maxbin.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        cp -r {input.assembly} {input.R1} {input.R2} $SCRATCHDIR
        mkdir -p $(dirname {output})
        cd $SCRATCHDIR

        echo -e "\nUnzipping assembly ... "
        gunzip $(basename {input.assembly})
        
        echo -e "\nRunning maxbin2 ... "
        run_MaxBin.pl -contig $(echo $(basename {input.assembly})|sed 's/.gz//') \
            -out $(basename $(dirname {output})) \
            -reads $(basename {input.R1}) \
            -reads2 $(basename {input.R2}) \
            -thread {config[cores][maxbin]}

        rm $(echo $(basename {input.assembly})|sed 's/.gz//')
        
        mkdir $(basename {output})
        mv *.fasta *.summary *.abundance *.abund1 *.abund2 $(basename {output})
        mv $(basename {output}) $(dirname {output})

        """

rule maxbinCross:
    input:
        assembly = rules.megahit.output,
        depth = f'{config["path"]["root"]}/{config["folder"]["maxbin"]}/{{IDs}}/cov'
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["maxbin"]}/{{IDs}}/{{IDs}}.maxbin-bins')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.maxbin.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        cp -r {input.assembly} {input.depth}/*.depth $SCRATCHDIR
        mkdir -p $(dirname {output})
        cd $SCRATCHDIR
        echo -e "\nUnzipping assembly ... "
        gunzip $(basename {input.assembly})
        echo -e "\nGenerating list of depth files based on crossMap rule output ... "
        find . -name "*.depth" > abund.list
        
        echo -e "\nRunning maxbin2 ... "
        run_MaxBin.pl -contig contigs.fasta -out $(basename $(dirname {output})) -abund_list abund.list
        rm *.depth abund.list contigs.fasta
        mkdir -p $(basename {output})
        mv *.fasta $(basename {output})
        mv * $(dirname {output})
        """


rule binRefine:
    input:
        concoct = f'{config["path"]["root"]}/{config["folder"]["concoct"]}/{{IDs}}/{{IDs}}.concoct-bins',
        metabat = f'{config["path"]["root"]}/{config["folder"]["metabat"]}/{{IDs}}/{{IDs}}.metabat-bins',
        maxbin = f'{config["path"]["root"]}/{config["folder"]["maxbin"]}/{{IDs}}/{{IDs}}.maxbin-bins'
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["refined"]}/{{IDs}}')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.binRefine.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metawrap]};set -u;
        mkdir -p $(dirname {output})
        mkdir -p {output}
        cd $SCRATCHDIR

        echo "Copying bins from CONCOCT, metabat2, and maxbin2 to $SCRATCHDIR ... "
        cp -r {input.concoct} {input.metabat} {input.maxbin} $SCRATCHDIR

        echo "Renaming bin folders to avoid errors with metaWRAP ... "
        mv $(basename {input.concoct}) $(echo $(basename {input.concoct})|sed 's/-bins//g')
        mv $(basename {input.metabat}) $(echo $(basename {input.metabat})|sed 's/-bins//g')
        mv $(basename {input.maxbin}) $(echo $(basename {input.maxbin})|sed 's/-bins//g')
        
        echo "Running metaWRAP bin refinement module ... "
        metaWRAP bin_refinement -o . \
            -A $(echo $(basename {input.concoct})|sed 's/-bins//g') \
            -B $(echo $(basename {input.metabat})|sed 's/-bins//g') \
            -C $(echo $(basename {input.maxbin})|sed 's/-bins//g') \
            -t {config[cores][refine]} \
            -m {config[params][refineMem]} \
            -c {config[params][refineComp]} \
            -x {config[params][refineCont]}
 
        rm -r $(echo $(basename {input.concoct})|sed 's/-bins//g') $(echo $(basename {input.metabat})|sed 's/-bins//g') $(echo $(basename {input.maxbin})|sed 's/-bins//g') work_files
        mv * {output}
        """


rule binReassemble:
    input:
        R1 = rules.qfilter.output.R1, 
        R2 = rules.qfilter.output.R2,
        refinedBins = rules.binRefine.output
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["reassembled"]}/{{IDs}}')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.binReassemble.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metawrap]};set -u;
        mkdir -p $(dirname {output})
        cp -r {input.refinedBins}/metawrap_*_bins {input.R1} {input.R2} $SCRATCHDIR
        cd $SCRATCHDIR
        
        echo "Running metaWRAP bin reassembly ... "
        metaWRAP reassemble_bins -o $(basename {output}) \
            -b metawrap_*_bins \
            -1 $(basename {input.R1}) \
            -2 $(basename {input.R2}) \
            -t {config[cores][reassemble]} \
            -m {config[params][reassembleMem]} \
            -c {config[params][reassembleComp]} \
            -x {config[params][reassembleCont]} \
            --parallel
        
        rm -r metawrap_*_bins
        rm -r $(basename {output})/work_files
        rm *.fastq.gz 
        mv * $(dirname {output})
        """


rule binningVis:
    input: 
        f'{config["path"]["root"]}'
    output: 
        text = f'{config["path"]["root"]}/{config["folder"]["stats"]}/reassembled_bins.stats',
        plot = f'{config["path"]["root"]}/{config["folder"]["stats"]}/binningVis.pdf'
    message:
        """
        Generate bar plot with number of bins and density plot of bin contigs, 
        total length, completeness, and contamination across different tools.
        """
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        
        # READ CONCOCT BINS

        echo "Generating concoct_bins.stats file containing bin ID, number of contigs, and length ... "
        cd {input}/{config[folder][concoct]}
        for folder in */;do 
            var=$(echo $folder|sed 's|/||g'); # Define sample name
            for bin in $folder*concoct-bins/*.fa;do 
                name=$(echo $bin | sed "s|^.*/|$var.bin.|g" | sed 's/.fa//g'); # Define bin name
                N=$(less $bin | grep -c ">");
                L=$(less $bin |grep ">"|cut -d '-' -f4|sed 's/len=//g'|awk '{{sum+=$1}}END{{print sum}}')
                echo "Reading bin $bin ... Contigs: $N , Length: $L "
                echo $name $N $L >> concoct_bins.stats;
            done;
        done
        mv *.stats {input}/{config[folder][reassembled]}
        echo "Done reading CONCOCT bins, moving concoct_bins.stats file to $(echo {input}/{config[folder][reassembled]}) ."

        # READ METABAT2 BINS

        echo "Generating metabat_bins.stats file containing bin ID, number of contigs, and length ... "
        cd {input}/{config[folder][metabat]}
        for folder in */;do 
            var=$(echo $folder | sed 's|/||'); # Define sample name
            for bin in $folder*metabat-bins/*.fa;do 
                name=$(echo $bin|sed 's/.fa//g'|sed 's|^.*/||g'|sed "s/^/$var./g"); # Define bin name
                N=$(less $bin | grep -c ">");
                L=$(less $bin |grep ">"|cut -d '-' -f4|sed 's/len=//g'|awk '{{sum+=$1}}END{{print sum}}')
                echo "Reading bin $bin ... Contigs: $N , Length: $L "
                echo $name $N $L >> metabat_bins.stats;
            done;
        done
        mv *.stats {input}/{config[folder][reassembled]}
        echo "Done reading metabat2 bins, moving metabat_bins.stats file to $(echo {input}/{config[folder][reassembled]}) ."

        # READ MAXBIN2 BINS

        echo "Generating maxbin_bins.stats file containing bin ID, number of contigs, and length ... "
        cd {input}/{config[folder][maxbin]}
        for folder in */;do
            for bin in $folder*maxbin-bins/*.fasta;do 
                name=$(echo $bin | sed 's/.fasta//g' | sed 's|^.*/||g');  # Define bin name
                N=$(less $bin | grep -c ">");
                L=$(less $bin |grep ">"|cut -d '-' -f4|sed 's/len=//g'|awk '{{sum+=$1}}END{{print sum}}')
                echo "Reading bin $bin ... Contigs: $N , Length: $L "
                echo $name $N $L >> maxbin_bins.stats;
            done;
        done
        mv *.stats {input}/{config[folder][reassembled]}
        echo "Done reading maxbin2 bins, moving maxbin_bins.stats file to $(echo {input}/{config[folder][reassembled]}) ."

        # READ METAWRAP REFINED BINS

        echo "Generating refined_bins.stats file containing bin ID, number of contigs, and length ... "
        cd {input}/{config[folder][refined]}
        for folder in */;do 
            samp=$(echo $folder | sed 's|/||'); # Define sample name 
            for bin in $folder*metawrap_*_bins/*.fa;do 
                name=$(echo $bin | sed 's/.fa//g'|sed 's|^.*/||g'|sed "s/^/$samp./g"); # Define bin name
                N=$(less $bin | grep -c ">");
                L=$(less $bin |grep ">"|cut -d '-' -f4|sed 's/len_//g'|awk '{{sum+=$1}}END{{print sum}}')
                echo "Reading bin $bin ... Contigs: $N , Length: $L "
                echo $name $N $L >> refined_bins.stats;
            done;
        done
        echo "Done reading metawrap refined bins ... "

        # READ METAWRAP REFINED CHECKM OUTPUT        
        
        echo "Generating CheckM summary files across samples: concoct.checkm, metabat.checkm, maxbin.checkm, and refined.checkm ... "
        for folder in */;do 
            var=$(echo $folder|sed 's|/||g'); # Define sample name
            paste $folder*concoct.stats|tail -n +2 | sed "s/^/$var.bin./g" >> concoct.checkm
            paste $folder*metabat.stats|tail -n +2 | sed "s/^/$var./g" >> metabat.checkm
            paste $folder*maxbin.stats|tail -n +2 >> maxbin.checkm
            paste $folder*metawrap_*_bins.stats|tail -n +2|sed "s/^/$var./g" >> refined.checkm
        done 
        echo "Done reading metawrap refined output, moving refined_bins.stats, concoct.checkm, metabat.checkm, maxbin.checkm, and refined.checkm files to $(echo {input}/{config[folder][reassembled]}) ."
        mv *.stats *.checkm {input}/{config[folder][reassembled]}

        # READ METAWRAP REASSEMBLED BINS

        echo "Generating reassembled_bins.stats file containing bin ID, number of contigs, and length ... "
        cd {input}/{config[folder][reassembled]}
        for folder in */;do 
            samp=$(echo $folder | sed 's|/||'); # Define sample name 
            for bin in $folder*reassembled_bins/*.fa;do 
                name=$(echo $bin | sed 's/.fa//g' | sed 's|^.*/||g' | sed "s/^/$samp./g"); # Define bin name
                N=$(less $bin | grep -c ">");

                # Need to check if bins are original (megahit-assembled) or strict/permissive (metaspades-assembled)
                if [[ $name == *.strict ]] || [[ $name == *.permissive ]];then
                    L=$(less $bin |grep ">"|cut -d '_' -f4|awk '{{sum+=$1}}END{{print sum}}')
                else
                    L=$(less $bin |grep ">"|cut -d '-' -f4|sed 's/len_//g'|awk '{{sum+=$1}}END{{print sum}}')
                fi

                echo "Reading bin $bin ... Contigs: $N , Length: $L "
                echo $name $N $L >> reassembled_bins.stats;
            done;
        done
        echo "Done reading metawrap reassembled bins ... "

        # READ METAWRAP REFINED CHECKM OUTPUT  

        echo "Generating CheckM summary file reassembled.checkm across samples for reassembled bins ... "
        for folder in */;do 
            var=$(echo $folder|sed 's|/||g');
            paste $folder*reassembled_bins.stats|tail -n +2|sed "s/^/$var./g";
        done >> reassembled.checkm
        echo "Done generating all statistics files for binning results ... running plotting script ... "

        # RUN PLOTTING R SCRIPT

        mv *.stats *.checkm {config[path][root]}/{config[folder][stats]}
        cd {config[path][root]}/{config[folder][stats]}

        Rscript {config[path][root]}/{config[folder][scripts]}/{config[scripts][binningVis]}
        rm Rplots.pdf # Delete redundant pdf file
        echo "Done. "
        """

rule abundance:
    input:
        bins = f'{config["path"]["root"]}/{config["folder"]["reassembled"]}/{{IDs}}/reassembled_bins',
        #bins = f'{config["path"]["root"]}/dna_bins_organized/{{IDs}}/',
        R1 = rules.qfilter.output.R1, 
        R2 = rules.qfilter.output.R2
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["abundance"]}/{{IDs}}')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.abundance.benchmark.txt'
    message:
        """
        Calculate bin abundance fraction using the following:

        binAbundanceFraction = ( X / Y / Z) * 1000000

        X = # of reads mapped to bin_i from sample_k
        Y = length of bin_i (bp)
        Z = # of reads mapped to all bins in sample_k

        Note: 1000000 scaling factor converts length in bp to Mbp
              Rule slightly modified for european datasets where input bins are in dna_bins_organized
              instead of metaWRAP reassembly output folder 

        """
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        mkdir -p {output}
        cd $SCRATCHDIR

        echo -e "\nCopying quality filtered paired end reads and generated MAGs to SCRATCHDIR ... "
        cp {input.R1} {input.R2} {input.bins}/* .

        echo -e "\nConcatenating all bins into one FASTA file ... "
        cat *.fa > $(basename {output}).fa

        echo -e "\nCreating bwa index for concatenated FASTA file ... "
        bwa index $(basename {output}).fa

        echo -e "\nMapping quality filtered paired end reads to concatenated FASTA file with bwa mem ... "
        bwa mem -t {config[cores][abundance]} $(basename {output}).fa \
            $(basename {input.R1}) $(basename {input.R2}) > $(basename {output}).sam

        echo -e "\nConverting SAM to BAM with samtools view ... "
        samtools view -@ {config[cores][abundance]} -Sb $(basename {output}).sam > $(basename {output}).bam

        echo -e "\nSorting BAM file with samtools sort ... "
        samtools sort -@ {config[cores][abundance]} -o $(basename {output}).sort.bam $(basename {output}).bam

        echo -e "\nExtracting stats from sorted BAM file with samtools flagstat ... "
        samtools flagstat $(basename {output}).sort.bam > map.stats

        echo -e "\nCopying sample_map.stats file to root/abundance/sample for bin concatenation and deleting temporary FASTA file ... "
        cp map.stats {output}/$(basename {output})_map.stats
        rm $(basename {output}).fa
        
        echo -e "\nRepeat procedure for each bin ... "
        for bin in *.fa;do

            echo -e "\nSetting up temporary sub-directory to map against bin $bin ... "
            mkdir -p $(echo "$bin"| sed "s/.fa//")
            mv $bin $(echo "$bin"| sed "s/.fa//")
            cd $(echo "$bin"| sed "s/.fa//")

            echo -e "\nCreating bwa index for bin $bin ... "
            bwa index $bin

            echo -e "\nMapping quality filtered paired end reads to bin $bin with bwa mem ... "
            bwa mem -t {config[cores][abundance]} $bin \
                ../$(basename {input.R1}) ../$(basename {input.R2}) > $(echo "$bin"|sed "s/.fa/.sam/")

            echo -e "\nConverting SAM to BAM with samtools view ... "
            samtools view -@ {config[cores][abundance]} -Sb $(echo "$bin"|sed "s/.fa/.sam/") > $(echo "$bin"|sed "s/.fa/.bam/")

            echo -e "\nSorting BAM file with samtools sort ... "
            samtools sort -@ {config[cores][abundance]} -o $(echo "$bin"|sed "s/.fa/.sort.bam/") $(echo "$bin"|sed "s/.fa/.bam/")

            echo -e "\nExtracting stats from sorted BAM file with samtools flagstat ... "
            samtools flagstat $(echo "$bin"|sed "s/.fa/.sort.bam/") > $(echo "$bin"|sed "s/.fa/.map/")

            echo -e "\nAppending bin length to bin.map stats file ... "
            echo -n "Bin Length = " >> $(echo "$bin"|sed "s/.fa/.map/")

            # Need to check if bins are original (megahit-assembled) or strict/permissive (metaspades-assembled)
            if [[ $bin == *.strict.fa ]] || [[ $bin == *.permissive.fa ]] || [[ $bin == *.s.fa ]] || [[ $bin == *.p.fa ]];then
                less $bin |grep ">"|cut -d '_' -f4|awk '{{sum+=$1}}END{{print sum}}' >> $(echo "$bin"|sed "s/.fa/.map/")
            else
                less $bin |grep ">"|cut -d '-' -f4|sed 's/len_//g'|awk '{{sum+=$1}}END{{print sum}}' >> $(echo "$bin"|sed "s/.fa/.map/")
            fi

            paste $(echo "$bin"|sed "s/.fa/.map/")

            echo -e "\nCalculating abundance for bin $bin ... "
            echo -n "$bin"|sed "s/.fa//" >> $(echo "$bin"|sed "s/.fa/.abund/")
            echo -n $'\t' >> $(echo "$bin"|sed "s/.fa/.abund/")

            X=$(less $(echo "$bin"|sed "s/.fa/.map/")|grep "mapped ("|awk -F' ' '{{print $1}}')
            Y=$(less $(echo "$bin"|sed "s/.fa/.map/")|tail -n 1|awk -F' ' '{{print $4}}')
            Z=$(less "../map.stats"|grep "mapped ("|awk -F' ' '{{print $1}}')
            awk -v x="$X" -v y="$Y" -v z="$Z" 'BEGIN{{print (x/y/z) * 1000000}}' >> $(echo "$bin"|sed "s/.fa/.abund/")
            
            paste $(echo "$bin"|sed "s/.fa/.abund/")
            
            echo -e "\nRemoving temporary files for bin $bin ... "
            rm $bin
            cp $(echo "$bin"|sed "s/.fa/.map/") {output}
            mv $(echo "$bin"|sed "s/.fa/.abund/") ../
            cd ..
            rm -r $(echo "$bin"| sed "s/.fa//")
        done

        echo -e "\nDone processing all bins, summarizing results into sample.abund file ... "
        cat *.abund > $(basename {output}).abund

        echo -ne "\nSumming calculated abundances to obtain normalization value ... "
        norm=$(less $(basename {output}).abund |awk '{{sum+=$2}}END{{print sum}}');
        echo $norm

        echo -e "\nGenerating column with abundances normalized between 0 and 1 ... "
        awk -v NORM="$norm" '{{printf $1"\t"$2"\t"$2/NORM"\\n"}}' $(basename {output}).abund > abundance.txt

        rm $(basename {output}).abund
        mv abundance.txt $(basename {output}).abund

        mv $(basename {output}).abund {output}
        """

rule GTDBtk:
    input: 
        f'{config["path"]["root"]}/dna_bins_organized/{{IDs}}'
    output:
        directory(f'{config["path"]["root"]}/GTDBtk/{{IDs}}')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.GTDBtk.benchmark.txt'
    message:
        """
        The folder dna_bins_organized assumes subfolders containing dna bins for refined and reassembled bins.
        Note: slightly modified inputs/outputs for european dataset.
        """
    shell:
        """
        set +u;source activate gtdbtk-tmp;set -u;
        export GTDBTK_DATA_PATH=/g/scb2/patil/zorrilla/conda/envs/gtdbtk/share/gtdbtk-1.1.0/db/

        cd $SCRATCHDIR
        cp -r {input} .

        gtdbtk classify_wf --genome_dir $(basename {input}) --out_dir GTDBtk -x fa --cpus {config[cores][gtdbtk]}
        mkdir -p {output}
        mv GTDBtk/* {output}

        """

rule GTDBtkVis:
    input: 
        f'{config["path"]["root"]}'
    output: 
        text = f'{config["path"]["root"]}/{config["folder"]["stats"]}/GTDBtk.stats',
        plot = f'{config["path"]["root"]}/{config["folder"]["stats"]}/GTDBtkVis.pdf'
    message:
        """
        Generate bar plot with most common taxa (n>15) and density plots with mapping statistics.
        """
    shell:
        """
        cd {input}

        # Summarize GTDBtk output across samples
        for folder in GTDBtk/*;do 
            samp=$(echo $folder|sed 's|^.*/||');
            cat $folder/classify/*summary.tsv;
        done > GTDBtk.stats

        # Clean up stats file
        header=$(head -n 1 GTDBtk.stats)
        sed -i '/other_related_references(genome_id,species_name,radius,ANI,AF)/d' GTDBtk.stats
        sed -i "1i$header" GTDBtk.stats

        # Summarize abundance estimates
        for folder in abundance/*;do 
            samp=$(echo $folder|sed 's|^.*/||');
            cat $folder/*.abund;
        done > abundance.stats 

        # Move files to stats folder
        mv GTDBtk.stats {config[path][root]}/{config[folder][stats]}
        mv abundance.stats {config[path][root]}/{config[folder][stats]}

        cd {config[path][root]}/{config[folder][stats]}
        Rscript {config[path][root]}/{config[folder][scripts]}/{config[scripts][GTDBtkVis]}
        rm Rplots.pdf # Delete redundant pdf file
        echo "Done. "
        """


rule classifyGenomes:
    input:
        bins = f'{config["path"]["root"]}/{config["folder"]["reassembled"]}/{{IDs}}/reassembled_bins',
        script = f'{config["path"]["root"]}/{config["folder"]["scripts"]}/classify-genomes'
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["classification"]}/{{IDs}}')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.classify-genomes.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        mkdir -p {output}
        cd $SCRATCHDIR
        cp -r {input.script}/* {input.bins}/* .

        echo "Begin classifying bins ... "
        for bin in *.fa; do
            echo -e "\nClassifying $bin ... "
            $PWD/classify-genomes $bin -t {config[cores][classify]} -o $(echo $bin|sed 's/.fa/.taxonomy/')
            cp *.taxonomy {output}
            rm *.taxonomy
            rm $bin 
        done
        echo "Done classifying bins. "
        """

rule taxonomyVis:
    input: 
        f'{config["path"]["root"]}/{config["folder"]["classification"]}'
    output: 
        text = f'{config["path"]["root"]}/{config["folder"]["stats"]}/classification.stats',
        plot = f'{config["path"]["root"]}/{config["folder"]["stats"]}/taxonomyVis.pdf'
    message:
        """
        Generate bar plot with most common taxa (n>15) and density plots with mapping statistics.
        """
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        cd {input}

        echo -e "\nBegin reading classification result files ... \n"
        for folder in */;do 

            for file in $folder*.taxonomy;do

                # Define sample ID to append to start of each bin name in summary file
                sample=$(echo $folder|sed 's|/||')

                # Define bin name with sample ID, shorten metaWRAP naming scheme (orig/permissive/strict)
                fasta=$(echo $file | sed 's|^.*/||' | sed 's/.taxonomy//g' | sed 's/orig/o/g' | sed 's/permissive/p/g' | sed 's/strict/s/g' | sed "s/^/$sample./g");

                # Extract NCBI ID 
                NCBI=$(less $file | grep NCBI | cut -d ' ' -f4);

                # Extract consensus taxonomy
                tax=$(less $file | grep tax | sed 's/Consensus taxonomy: //g');

                # Extract consensus motus
                motu=$(less $file | grep mOTUs | sed 's/Consensus mOTUs: //g');

                # Extract number of detected genes
                detect=$(less $file | grep detected | sed 's/Number of detected genes: //g');

                # Extract percentage of agreeing genes
                percent=$(less $file | grep agreeing | sed 's/Percentage of agreeing genes: //g' | sed 's/%//g');

                # Extract number of mapped genes
                map=$(less $file | grep mapped | sed 's/Number of mapped genes: //g');
                
                # Extract COG IDs, need to use set +e;...;set -e to avoid erroring out when reading .taxonomy result file for bin with no taxonomic annotation
                set +e
                cog=$(less $file | grep COG | cut -d$'\t' -f1 | tr '\n' ',' | sed 's/,$//g');
                set -e
                
                # Display and store extracted results
                echo -e "$fasta \t $NCBI \t $tax \t $motu \t $detect \t $map \t $percent \t $cog"
                echo -e "$fasta \t $NCBI \t $tax \t $motu \t $detect \t $map \t $percent \t $cog" >> classification.stats;
            
            done;
        
        done

        echo -e "\nDone generating classification.stats summary file, moving to stats/ directory and running taxonomyVis.R script ... "
        mv classification.stats {config[path][root]}/{config[folder][stats]}
        cd {config[path][root]}/{config[folder][stats]}

        Rscript {config[path][root]}/{config[folder][scripts]}/{config[scripts][taxonomyVis]}
        rm Rplots.pdf # Delete redundant pdf file
        echo "Done. "
        """


rule parseTaxAb:
    input:
        taxonomy = rules.taxonomyVis.output.text ,
        abundance = f'{config["path"]["root"]}/{config["folder"]["abundance"]}'
    output:
        directory(f'{config["path"]["root"]}/MAG.table')
    message:
        """
        Parses an abundance table with MAG taxonomy for rows and samples for columns.
        Note: parseTaxAb should only be run after the classifyGenomes, taxonomyVis, and abundance rules.
        """
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u
        cd {input.abundance}

        for folder in */;do

            # Define sample ID
            sample=$(echo $folder|sed 's|/||g')
            
            # Same as in taxonomyVis rule, modify bin names by adding sample ID and shortening metaWRAP naming scheme (orig/permissive/strict)
            paste $sample/$sample.abund | sed 's/orig/o/g' | sed 's/permissive/p/g' | sed 's/strict/s/g' | sed "s/^/$sample./g" >> abundance.stats
       
        done

        mv abundance.stats {config[path][root]}/{config[folder][stats]}
        cd {config[path][root]}/{config[folder][stats]}

        """

rule extractProteinBins:
    message:
        "Extract ORF annotated protein fasta files for each bin from reassembly checkm files."
    shell:
        """
        cd {config[path][root]}
        mkdir -p {config[folder][proteinBins]}

        echo -e "Begin moving and renaming ORF annotated protein fasta bins from reassembled_bins/ to protein_bins/ ... \n"
        for folder in reassembled_bins/*/;do 
            echo "Moving bins from sample $(echo $(basename $folder)) ... "
            for bin in $folder*reassembled_bins.checkm/bins/*;do 
                var=$(echo $bin/genes.faa | sed 's|reassembled_bins/||g'|sed 's|/reassembled_bins.checkm/bins||'|sed 's|/genes||g'|sed 's|/|_|g'|sed 's/permissive/p/g'|sed 's/orig/o/g'|sed 's/strict/s/g');
                cp $bin/*.faa {config[path][root]}/{config[folder][proteinBins]}/$var;
            done;
        done
        """


rule carveme:
    input:
        bin = f'{config["path"]["root"]}/{config["folder"]["proteinBins"]}/{{binIDs}}.faa',
        media = f'{config["path"]["root"]}/{config["folder"]["scripts"]}/{config["scripts"]["carveme"]}'
    output:
        f'{config["path"]["root"]}/{config["folder"]["GEMs"]}/{{binIDs}}.xml'
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{binIDs}}.carveme.benchmark.txt'
    message:
        """
        Make sure that the input files are ORF annotated and preferably protein fasta.
        If given raw fasta files, Carveme will run without errors but each contig will be treated as one gene.
        """
    shell:
        """
        echo "Activating {config[envs][metabagpipes]} conda environment ... "
        set +u;source activate {config[envs][metabagpipes]};set -u
        
        mkdir -p $(dirname {output})
        mkdir -p logs

        cp {input.bin} {input.media} $SCRATCHDIR
        cd $SCRATCHDIR
        
        echo "Begin carving GEM ... "
        carve -g {config[params][carveMedia]} \
            -v \
            --mediadb $(basename {input.media}) \
            --fbc2 \
            -o $(echo $(basename {input.bin}) | sed 's/.faa/.xml/g') $(basename {input.bin})
        
        echo "Done carving GEM. "
        [ -f *.xml ] && mv *.xml $(dirname {output})
        """


rule modelVis:
    input: 
        f'{config["path"]["root"]}/{config["folder"]["GEMs"]}'
    output: 
        text = f'{config["path"]["root"]}/{config["folder"]["stats"]}/GEMs.stats',
        plot = f'{config["path"]["root"]}/{config["folder"]["stats"]}/modelVis.pdf'
    message:
        """
        Generate bar plot with GEMs generated across samples and density plots showing number of 
        unique metabolites, reactions, and genes across GEMs.
        """
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        cd {input}

        echo -e "\nBegin reading models ... \n"
        for model in *.xml;do 
            id=$(echo $model|sed 's/.xml//g'); 
            mets=$(less $model| grep "species id="|cut -d ' ' -f 8|sed 's/..$//g'|sort|uniq|wc -l);
            rxns=$(less $model|grep -c 'reaction id=');
            genes=$(less $model|grep 'fbc:geneProduct fbc:id='|grep -vic spontaneous);
            echo "Model: $id has $mets mets, $rxns reactions, and $genes genes ... "
            echo "$id $mets $rxns $genes" >> GEMs.stats;
        done

        echo -e "\nDone generating GEMs.stats summary file, moving to stats/ folder and running modelVis.R script ... "
        mv GEMs.stats {config[path][root]}/{config[folder][stats]}
        cd {config[path][root]}/{config[folder][stats]}

        Rscript {config[path][root]}/{config[folder][scripts]}/{config[scripts][modelVis]}
        rm Rplots.pdf # Delete redundant pdf file
        echo "Done. "
        """

rule ECvis:
    input: 
        f'{config["path"]["root"]}/{config["folder"]["GEMs"]}'
    output:
        directory(f'{config["path"]["root"]}/ecfiles')
    message:
        """
        Get EC information from GEMs. 
        Switch the input folder and grep|sed expressions to match the ec numbers in you model sets.
        Currently configured for UHGG GEM set.
        """
    shell:
        """
        echo -e "\nCopying GEMs from specified input directory to SCRATCHDIR ... "
        cp -r {input} $SCRATCHDIR

        cd $SCRATCHDIR
        mkdir ecfiles

        while read model; do

            # Read E.C. numbers from  each sbml file and write to a unique file, note that grep expression is hardcoded for specific GEM batches           
            less $(basename {input})/$model|
                grep 'EC Number'| \
                sed 's/^.*: //g'| \
                sed 's/<.*$//g'| \
                sed '/-/d'|sed '/N\/A/d' | \
                sort|uniq -c \
            > ecfiles/$model.ec

            echo -ne "Reading E.C. numbers in model $model, unique E.C. : "
            ECNUM=$(less ecfiles/$model.ec|wc -l)
            echo $ECNUM

        done< <(ls $(basename {input}))

        echo -e "\nMoving ecfiles folder back to {config[path][root]}"
        mv ecfiles {config[path][root]}
        cd {config[path][root]}

        echo -e "\nCreating sorted unique file EC.summary for easy EC inspection ... "
        cat ecfiles/*.ec|awk '{{print $NF}}'|sort|uniq -c > EC.summary

        paste EC.summary

        """

rule organizeGEMs:
    input:
        f'{config["path"]["root"]}/{config["folder"]["refined"]}'
    message:
        """
        Organizes GEMs into sample specific subfolders. 
        Necessary to run smetana per sample using the IDs wildcard.
        """
    shell:
        """
        cd {input}
        for folder in */;do
            echo -n "Creating GEM subfolder for sample $folder ... "
            mkdir -p ../{config[folder][GEMs]}/$folder;
            echo -n "moving GEMs ... "
            mv ../{config[folder][GEMs]}/$(echo $folder|sed 's|/||')_*.xml ../{config[folder][GEMs]}/$folder;
            echo "done. "
        done
        """


rule smetana:
    input:
        f'{config["path"]["root"]}/{config["folder"]["GEMs"]}/{{IDs}}'
    output:
        f'{config["path"]["root"]}/{config["folder"]["SMETANA"]}/{{IDs}}_detailed.tsv'
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.smetana.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u
        mkdir -p {config[path][root]}/{config[folder][SMETANA]}
        cp {config[path][root]}/{config[folder][scripts]}/{config[scripts][carveme]} {input}/*.xml $SCRATCHDIR
        cd $SCRATCHDIR
        
        smetana -o $(basename {input}) --flavor fbc2 \
            --mediadb media_db.tsv -m {config[params][smetanaMedia]} \
            --detailed \
            --solver {config[params][smetanaSolver]} -v *.xml
        
        cp *.tsv {config[path][root]} #safety measure for backup of results in case rule fails for some reason
        mv *.tsv $(dirname {output})
        """


rule interactionVis:
    input:
        f'{config["path"]["root"]}/{config["folder"]["SMETANA"]}'
    shell:
        """
        cd {input}
        mv media_db.tsv ../scripts/
        cat *.tsv|sed '/community/d' > smetana.all
        less smetana.all |cut -f2|sort|uniq > media.txt
        ll|grep tsv|awk '{print $NF}'|sed 's/_.*$//g'>samples.txt
        while read sample;do echo -n "$sample ";while read media;do var=$(less smetana.all|grep $sample|grep -c $media); echo -n "$var " ;done < media.txt; echo "";done < samples.txt > sampleMedia.stats
        """


rule memote:
    input:
        f'{config["path"]["root"]}/{config["folder"]["GEMs"]}/{{gemIDs}}.xml'
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["memote"]}/{{gemIDs}}')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{gemIDs}}.memote.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u
        module load git

        mkdir -p {output}
        cp {input} $SCRATCHDIR
        cd $SCRATCHDIR

        memote report snapshot --skip test_find_metabolites_produced_with_closed_bounds --skip test_find_metabolites_consumed_with_closed_bounds --skip test_find_metabolites_not_produced_with_open_bounds --skip test_find_metabolites_not_consumed_with_open_bounds --skip test_find_incorrect_thermodynamic_reversibility --filename $(echo $(basename {input})|sed 's/.xml/.html/') *.xml
        memote run --skip test_find_metabolites_produced_with_closed_bounds --skip test_find_metabolites_consumed_with_closed_bounds --skip test_find_metabolites_not_produced_with_open_bounds --skip test_find_metabolites_not_consumed_with_open_bounds --skip test_find_incorrect_thermodynamic_reversibility *.xml

        mv result.json.gz $(echo $(basename {input})|sed 's/.xml/.json.gz/')

        mv *.gz *.html {output}

        """


rule grid:
    input:
        bins = f'{config["path"]["root"]}/{config["folder"]["reassembled"]}/{{IDs}}/reassembled_bins',
        R1 = rules.qfilter.output.R1, 
        R2 = rules.qfilter.output.R2
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["GRiD"]}/{{IDs}}')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.grid.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u

        cp -r {input.bins} {input.R1} {input.R2} $SCRATCHDIR
        cd $SCRATCHDIR

        cat *.gz > $(basename $(dirname {input.bins})).fastq.gz
        rm $(basename {input.R1}) $(basename {input.R2})

        mkdir MAGdb out
        update_database -d MAGdb -g $(basename {input.bins}) -p MAGdb
        rm -r $(basename {input.bins})

        grid multiplex -r . -e fastq.gz -d MAGdb -p -c 0.2 -o out -n {config[cores][grid]}

        rm $(basename $(dirname {input.bins})).fastq.gz
        mkdir {output}
        mv out/* {output}
        """


rule extractDnaBins:
    message:
        "Extract dna fasta files for each bin from reassembly output."
    shell:
        """
        cd {config[path][root]}
        mkdir -p {config[folder][dnaBins]}

        echo -e "Begin copying and renaming dna fasta bins from reassembled_bins/ to dna_bins/ ... \n"
        for folder in reassembled_bins/*/;do 
            echo "Copying bins from sample $(echo $(basename $folder)) ... "
            for bin in $folder*reassembled_bins/*;do 
                var=$(echo $bin| sed 's|reassembled_bins/||g'|sed 's|/|\.|g');
                cp $bin {config[path][root]}/{config[folder][dnaBins]}/$var;
            done;
        done
        """


rule prokka:
    input:
        bins = f'{config["path"]["root"]}/{config["folder"]["dnaBins"]}/{{binIDs}}.fa'
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["pangenome"]}/prokka/unorganized/{{binIDs}}')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{binIDs}}.prokka.benchmark.txt'
    shell:
        """
        set +u;source activate prokkaroary;set -u
        mkdir -p $(dirname $(dirname {output}))
        mkdir -p $(dirname {output})

        cp {input} $SCRATCHDIR
        cd $SCRATCHDIR

        id=$(echo $(basename {input})|sed "s/.fa//g")
        prokka -locustag $id --cpus {config[cores][prokka]} --centre MAG --compliant -outdir prokka/$id -prefix $id $(basename {input})

        mv prokka/$id $(dirname {output})
        """

rule prepareRoary:
    input:
        taxonomy = rules.GTDBtkVis.output.text,
        binning = rules.binningVis.output.text,
        script = f'{config["path"]["root"]}/{config["folder"]["scripts"]}/{config["scripts"]["prepRoary"]}'
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["pangenome"]}/speciesBinIDs')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/prepareRoary.benchmark.txt'
    message:
        """
        This rule matches the results from classifyGenomes->taxonomyVis with the completeness & contamination
        CheckM results from the metaWRAP reassembly->binningVis results, identifies speceies represented by 
        at least 10 high quality MAGs (completeness >= 90 & contamination <= 10), and outputs text files 
        with bin IDs for each such species. Also organizes the prokka output folders based on taxonomy.
        Note: Do not run this before finishing all prokka jobs!
        """
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u
        cd $(dirname {input.taxonomy})

        echo -e "\nCreating speciesBinIDs folder containing.txt files with binIDs for each species that is represented by at least 10 high quality MAGs (completeness >= 90 & contamination <= 10) ... "
        Rscript {input.script}

        nSpecies=$(ls $(basename {output})|wc -l)
        nSpeciesTot=$(cat $(basename {output})/*|wc -l)
        nMAGsTot=$(paste {input.binning}|wc -l)
        echo -e "\nIdentified $nSpecies species represented by at least 10 high quality MAGs, totaling $nSpeciesTot MAGs out of $nMAGsTot total MAGs generated ... "

        echo -e "\nMoving speciesBinIDs folder to pangenome directory: $(dirname {output})"
        mv $(basename {output}) $(dirname {output})

        echo -e "\nOrganizing prokka folder according to taxonomy ... "
        echo -e "\nGFF files of identified species with at least 10 HQ MAGs will be copied to prokka/organzied/speciesSubfolder for roary input ... "
        cd $(dirname {output})
        mkdir -p prokka/organized

        for species in speciesBinIDs/*.txt;do

            speciesID=$(echo $(basename $species)|sed 's/.txt//g');
            echo -e "\nCreating folder and organizing prokka output for species $speciesID ... "
            mkdir -p prokka/organized/$speciesID

            while read line;do
                
                binID=$(echo $line|sed 's/.bin/_bin/g')
                echo "Copying GFF prokka output of bin $binID"
                cp prokka/unorganized/$binID/*.gff prokka/organized/$speciesID/

            done< $species
        done

        echo -e "\nDone"
        """ 


rule prepareRoaryMOTUS2:
    input:
        taxonomy = rules.taxonomyVis.output.text,
        binning = rules.binningVis.output.text,
        script = f'{config["path"]["root"]}/{config["folder"]["scripts"]}/{config["scripts"]["prepRoary"]}'
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["pangenome"]}/speciesBinIDs')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/prepareRoary.benchmark.txt'
    message:
        """
        This rule matches the results from classifyGenomes->taxonomyVis with the completeness & contamination
        CheckM results from the metaWRAP reassembly->binningVis results, identifies speceies represented by 
        at least 10 high quality MAGs (completeness >= 90 & contamination <= 10), and outputs text files 
        with bin IDs for each such species. Also organizes the prokka output folders based on taxonomy.
        Note: Do not run this before finishing all prokka jobs!
        """
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u
        cd $(dirname {input.taxonomy})

        echo -e "\nCreating speciesBinIDs folder containing.txt files with binIDs for each species that is represented by at least 10 high quality MAGs (completeness >= 90 & contamination <= 10) ... "
        Rscript {input.script}

        nSpecies=$(ls $(basename {output})|wc -l)
        nSpeciesTot=$(cat $(basename {output})/*|wc -l)
        nMAGsTot=$(paste {input.binning}|wc -l)
        echo -e "\nIdentified $nSpecies species represented by at least 10 high quality MAGs, totaling $nSpeciesTot MAGs out of $nMAGsTot total MAGs generated ... "

        echo -e "\nMoving speciesBinIDs folder to pangenome directory: $(dirname {output})"
        mv $(basename {output}) $(dirname {output})

        echo -e "\nOrganizing prokka folder according to taxonomy ... "
        echo -e "\nGFF files of identified species with at least 10 HQ MAGs will be copied to prokka/organzied/speciesSubfolder for roary input ... "
        cd $(dirname {output})
        mkdir -p prokka/organized

        for species in speciesBinIDs/*.txt;do

            speciesID=$(echo $(basename $species)|sed 's/.txt//g');
            echo -e "\nCreating folder and organizing prokka output for species $speciesID ... "
            mkdir -p prokka/organized/$speciesID

            while read line;do
                
                binID=$(echo $line|sed 's/.bin/_bin/g')
                echo "Copying GFF prokka output of bin $binID"
                cp prokka/unorganized/$binID/*.gff prokka/organized/$speciesID/

            done< $species
        done

        echo -e "\nDone"
        """ 


rule roary:
    input:
        f'{config["path"]["root"]}/{config["folder"]["pangenome"]}/prokka/organized/{{speciesIDs}}/'
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["pangenome"]}/roary/{{speciesIDs}}/')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{speciesIDs}}.roary.benchmark.txt'
    shell:
        """
        set +u;source activate prokkaroary;set -u
        mkdir -p $(dirname {output})
        cd $SCRATCHDIR
        cp -r {input} .
                
        roary -s -p {config[cores][roary]} -i {config[params][roaryI]} -cd {config[params][roaryCD]} -f yes_al -e -v $(basename {input})/*.gff
        cd yes_al
        create_pan_genome_plots.R 
        cd ..
        mkdir -p {output}

        mv yes_al/* {output}
        """

rule roaryTop10:
    input:
        f'{config["path"]["root"]}/{config["folder"]["pangenome"]}/prokka/organized/'
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["pangenome"]}/roary/top10/')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/roaryTop10.roary.benchmark.txt'
    message:
        """
        Runs pangenome for ~692 MAGs belonging to 10 species:
        Agathobacter rectale, Bacteroides uniformis, 
        Ruminococcus_E bromii_B, Gemmiger sp003476825, 
        Blautia_A wexlerae, Dialister invisus,
        Anaerostipes hadrus, Fusicatenibacter saccharivorans,
        Eubacterium_E hallii, and NA
        """
    shell:
        """
        set +u;source activate prokkaroary;set -u
        mkdir -p $(dirname {output})
        cd $SCRATCHDIR

        cp -r {input}/Agathobacter_rectale/* . 
        cp -r {input}/Bacteroides_uniformis/* . 
        cp -r {input}/Ruminococcus_E_bromii_B/* . 
        cp -r {input}/Gemmiger_sp003476825/* . 
        cp -r {input}/Blautia_A_wexlerae/* .
        cp -r {input}/Dialister_invisus/* . 
        cp -r {input}/Anaerostipes_hadrus/* . 
        cp -r {input}/Fusicatenibacter_saccharivorans/* . 
        cp -r {input}/Eubacterium_E_hallii/* . 
        cp -r {input}/NA/* .
                
        roary -s -p {config[cores][roary]} -i {config[params][roaryI]} -cd {config[params][roaryCD]} -f yes_al -e -v *.gff
        cd yes_al
        create_pan_genome_plots.R 
        cd ..
        mkdir -p {output}

        mv yes_al/* {output}
        """


rule drep:
    input:
        f'{config["path"]["root"]}/dna_bins'
    output:
        directory(f'{config["path"]["root"]}/drep_drep')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/drep_drep.benchmark.txt'
    shell:
        """
        set +u;source activate drep;set -u
        cp -r {input} $SCRATCHDIR
        cd $SCRATCHDIR

        dRep dereplicate drep_drep -g $(basename {input})/*.fa -p 48 -comp 50 -con 10
        mv drep_drep $(dirname {input})
        """

rule drepComp:
    input:
        f'{config["path"]["root"]}/dna_bins'
    output:
        directory(f'{config["path"]["root"]}/drep_comp')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/drep_comp.benchmark.txt'
    shell:
        """
        set +u;source activate drep;set -u
        cp -r {input} $SCRATCHDIR
        cd $SCRATCHDIR

        dRep compare drep_comp -g $(basename {input})/*.fa -p 48
        mv drep_comp $(dirname {input})
        """

rule phylophlan:
    input:
        f'/home/zorrilla/workspace/european/dna_bins'
    output:
        directory(f'/scratch/zorrilla/phlan/out')
    benchmark:
        f'/scratch/zorrilla/phlan/logs/bench.txt'
    shell:
        """
        cd $SCRATCHDIR
        cp -r {input} . 
        cp $(dirname {output})/*.cfg .
        mkdir -p logs

        phylophlan -i dna_bins \
                    -d phylophlan \
                    -f 02_tol.cfg \
                    --genome_extension fa \
                    --diversity low \
                    --fast \
                    -o out \
                    --nproc 128 \
                    --verbose 2>&1 | tee logs/phylophlan.logs

        cp -r out $(dirname {output})
        """

rule phylophlanPlant:
    input:
        f'/home/zorrilla/workspace/china_soil/dna_bins'
    output:
        directory(f'/home/zorrilla/workspace/china_soil/phlan/')
    benchmark:
        f'/scratch/zorrilla/phlan/logs/benchPlant.txt'
    shell:
        """
        cd $SCRATCHDIR
        cp -r {input} . 
        cp /scratch/zorrilla/phlan/*.cfg .
        mkdir -p logs

        phylophlan -i dna_bins \
                    -d phylophlan \
                    -f 02_tol.cfg \
                    --genome_extension fa \
                    --diversity low \
                    --fast \
                    -o $(basename {output}) \
                    --nproc 128 \
                    --verbose 2>&1 | tee logs/phylophlan.logs

        cp -r $(basename {output}) $(dirname {output})
        """
        
rule phylophlanMeta:
    input:
        f'/home/zorrilla/workspace/european/dna_bins'
    output:
        directory(f'/home/zorrilla/workspace/european/phlan/dist')
    benchmark:
        f'/scratch/zorrilla/phlan/logs/bench.txt'
    shell:
        """
        cd {input}
        cd ../

        phylophlan_metagenomic -i $(basename {input}) -o $(basename {output})_dist --nproc 2 --only_input
    
        mv $(basename {output})_dist $(basename {output})
        mv -r $(basename {output}) $(dirname {output})
        """


rule phylophlanMetaAll:
    input:
        lab=f'/home/zorrilla/workspace/korem/dna_bins',
        gut=f'/home/zorrilla/workspace/european/dna_bins' ,
        plant=f'/home/zorrilla/workspace/china_soil/dna_bins' ,
        soil=f'/home/zorrilla/workspace/straya/dna_bins' ,
        ocean=f'/scratch/zorrilla/dna_bins' 
    output:
        directory(f'/home/zorrilla/workspace/european/phlan/all')
    benchmark:
        f'/scratch/zorrilla/phlan/logs/allMetaBench.txt'
    shell:
        """
        mkdir -p {output}
        cd $SCRATCHDIR

        mkdir allMAGs
        cp {input.lab}/* allMAGs
        cp {input.gut}/* allMAGs
        cp {input.plant}/* allMAGs
        cp {input.soil}/* allMAGs
        cp {input.ocean}/* allMAGs

        phylophlan_metagenomic -i allMAGs -o all --nproc 4 --only_input
        mv all_distmat.tsv $(dirname {output})
        """

rule drawTree:
    input:
        f'/home/zorrilla/workspace/china_soil/phlan'
    shell:
        """
        cd {input}
        graphlan.py dna_bins.tre.iqtree tree.out
        """

rule makePCA:
    input:
        f'/home/zorrilla/workspace/european/phlan'
    shell:
        """
        cd $SCRATCHDIR
        echo -e "\nCopying files to scratch dir: $SCRATCHDIR"
        cp {input}/*.tsv {input}/*.ids {input}/*.R .

        echo -e "\nRunning nmds.R script ... "
        Rscript nmds.R
        rm *.tsv *.ids *.R

        mkdir -p nmds
        mv *.pdf nmds
        mv nmds {input}
        """


