#!/usr/bin/Rscript

args = commandArgs(T)

library(peakPick)
library(ggplot2)
library(gridExtra)

#count.file = args[1]
svtype = args[1]
chrs = args[2]
peakPick.win = as.numeric(args[3])
peakPick.minsd = as.numeric(args[4])
pct.samples.cutoff = as.numeric(args[5])
out.dir = args[6]
distance = as.numeric(args[7])
merg.pct.samp = as.numeric(args[8])
stop.merge.num.peaks = as.numeric(args[9])
genes.of.int <- args[10]
chr.size.file = args[11]

### read all break points
bp = read.table(paste0(out.dir,'/processed_data/all_bp.bed'), header=F, sep='\t', quote='', stringsAsFactors=F)
colnames(bp) = c('chr', 'start', 'stop', 'name', 'score', 'strand')
bp$sample = gsub('/.*$', '', bp$name)
bp$svtype = gsub('^.*/', '', bp$name)
### extract total number of samples 
total.samples <- length(unique(bp$sample))

### read sample counts file
if (file.exists(paste0(out.dir,'/processed_data/counts.rds')) ){
  cat('Reading sliding window sample count...\n')
  counts = readRDS(paste0(out.dir,'/processed_data/counts.rds'))
} else {
  stop ("File \"counts.rds\" was not found, make sure this file exists.\n")
}

### extract chromosome names 
chr = read.table(chr.size.file, header=T, stringsAsFactors=F, sep='\t')
if (chrs == "ALL"){
    chr.names.found = chr$chrom
} else {
    chr.names.found = unlist(strsplit(chrs,  ",")) 
    cat('Chromosomes to analyze:\n')
    print (chr.names.found)
}

#chrs = intersect(chrs, unique(counts$chr))
#cat('Chromosomes to analyze:\n')
#print(chrs)

### read genes of interest file if provided 
if (genes.of.int !=0) {
  genes.of.interes = read.table(genes.of.int, header=F, stringsAsFactors=F)
  colnames(genes.of.interes) = c('chr', 'start', 'stop', 'gene')
  genes.of.interes$pos = (genes.of.interes$start + genes.of.interes$stop)/2
  genes.of.interes = genes.of.interes[, c('chr', 'pos', 'gene')]
  genes.of.interes = unique(genes.of.interes)
}

###################### FUNCTION CAL PEAKS USING peakPick algorithm ############################
pp <- function(x) {
   mat = as.matrix(data.frame(a=1, b=x$pct.samples))
   if (nrow(x) > peakPick.win) {
     h <- detect.spikes(mat, roi=c(peakPick.win+1, nrow(x)-peakPick.win-1), winlen=peakPick.win, spike.min.sd=peakPick.minsd)
   } else {
     h <- peakpick(mat, 10, peak.npos=5)
   }
    return (h)
}
###############################################################################################

############################### CALL PEAKS USING smoothed z-score #############################
ThresholdingAlgo <- function(y,lag,threshold,influence) {
  signals <- rep(0,length(y))
  filteredY <- y[0:lag]
  avgFilter <- NULL
  stdFilter <- NULL
  avgFilter[lag] <- mean(y[0:lag])
  stdFilter[lag] <- sd(y[0:lag])
  for (i in (lag+1):length(y)){
    if (abs(y[i]-avgFilter[i-1]) > threshold*stdFilter[i-1]) {
      if (y[i] > avgFilter[i-1]) {
        signals[i] <- 1;
      } else {
        signals[i] <- -1;
      }
      filteredY[i] <- influence*y[i]+(1-influence)*filteredY[i-1]
    } else {
      signals[i] <- 0
      filteredY[i] <- y[i]
    }
    avgFilter[i] <- mean(filteredY[(i-lag):i])
    stdFilter[i] <- sd(filteredY[(i-lag):i])
  }
  return(list("signals"=signals,"avgFilter"=avgFilter,"stdFilter"=stdFilter))
}
###############################################################################################

####################### FUNCTION TO COMPUTE NUMBER AND PERCENTAGE OF SAMPLES ##################
computePCT.samples <- function(data, group.data) {
  groups = group.data$group
  gr.data = NULL
  for (g in groups) {
    gr.samples = unique(unlist(strsplit(data[!is.na(data$group) & data$group==g, 'sample'], ",")))
    gr.num.samples = length(gr.samples)
    gr.pct.samples = gr.num.samples/total.samples * 100
    d = data.frame(group=g, num.samples=gr.num.samples, pct.samples=gr.pct.samples, sample=paste(gr.samples, collapse=","))
    gr.data = rbind(gr.data, d)
  }
  return (gr.data)
}
###############################################################################################

############################# FUNCTION TO GROUP NEAREST PEAKS #################################
mergePeaks <- function(x, merge.pct.samples, new.pks.cutoff){
  
  ## extract all clusters 
  clusters <- unique(x$cluster)[!is.na(unique(x$cluster))]
  merged_peaks <- NULL
  for (i in 1:length(clusters)) {
    cl <- clusters[i]
    xx <- x[!is.na(x$cluster) & x$cluster == cl, ]
    
    ## merge peaks 
    if (nrow(xx) > 1 ) {
      xx = xx[order(xx$pos),]
      top.peak = xx$pos[xx$pct.samples == max(xx$pct.samples)]
      if (length(top.peak) > 1) {
        top.peak = sample(top.peak, 1)
      }
      top.peak = which(xx$pos == top.peak)
      top.pct.samples <- xx[top.peak, 'pct.samples']
      #peaks = xx$pos  ### will be deleted 
      peaks =  which(xx$peak)
      peaks = peaks[peaks != top.peak]
      first.top.peak = top.peak
      
      xx$group = NA
      group = 1
      xx$group[top.peak] = as.numeric(paste0(cl,'.',group))
      left.peaks <- peaks[peaks < top.peak]
      right.peaks <- peaks[peaks > top.peak]
      
      ### loop through peaks located at the left to the top peak
      if (length(left.peaks)> 0) {
        num.new.peak = 0
        for (pk in rev(left.peaks)){
          if ( abs((xx$pct.samples[pk]  - top.pct.samples)) > merge.pct.samples) {
            num.new.peak = num.new.peak + 1
            if (num.new.peak > new.pks.cutoff) {
              group = group + 1
              top.peak = pk
              top.pct.samples <- xx[top.peak, 'pct.samples']
              num.new.peak = 0
            } else {
              xx$group[pk] = as.numeric(paste0(cl,'.',group))
            }
          }
          xx$group[pk] =as.numeric(paste0(cl,'.',group))
        }
      }
   
      
      ### loop through peaks located at the right of the top peak
      if (length(right.peaks) > 0 ) {
        top.peak = first.top.peak
        top.pct.samples <- xx[top.peak, 'pct.samples']
        last.group =  group
        group = 1
        num.new.peak = 0
        for (k in 1:length(right.peaks)){
          pk = right.peaks[k]
          if ( abs((xx$pct.samples[pk]  - top.pct.samples)) > merge.pct.samples) {
            num.new.peak = num.new.peak + 1
            if (num.new.peak > new.pks.cutoff) {
              last.group = last.group + 1
              top.peak = pk
              top.pct.samples <- xx[top.peak, 'pct.samples']
              xx$group[pk] = paste0(cl, '.', last.group)
              group = last.group
              num.new.peak = 0
            } else {
              xx$group[pk] =  paste0(cl,'.',group)
            }
            
          } else {
            xx$group[pk] =  paste0(cl,'.',group)
          }
          
        } ## end of FOR LOOP
      }
     
      
      ## combine all 
      merged_peaks <- rbind(merged_peaks, xx)
      
    } else {
      xx$group <- paste0(cl,'.',1)
      merged_peaks <- rbind(merged_peaks, xx)
    }
    
  }   ### end clusters 
  
  return(merged_peaks)
}

groupPeaks <- function(x, d){
    ## define clusters 
    x = x[order(x$pos),]
    peaks =  which(x$peak)
    last.peak = peaks[1]
    x$cluster = NA
    cluster = 1
    for (pk in peaks){
        if (x$pos[pk] > x$pos[last.peak] + d){
          cluster = cluster + 1
        }
        x$cluster[pk] = cluster
        last.peak = pk
    }

    ## merge peaks based on percentage of samples similarity 
    merged.peaks = mergePeaks(x, merg.pct.samp, stop.merge.num.peaks)
   
    num.peak.groups = length(unique(merged.peaks$group[!is.na(merged.peaks$group)]))
    cat('Number of peaks: ', num.peak.groups, '\n')
    
    ## keep max peaks
    #x = as.data.table(x[!is.na(x$group), ])
    #x = as.data.frame(x[x[, .I[pct.samples == max(pct.samples)], by = group]$V1])

    # produce bed file
    gr = NULL
    if (num.peak.groups > 0){
        z = merged.peaks[order(merged.peaks$pos),]
        start = z[!is.na(z$group) & !duplicated(z$group), c('chr', 'start', 'group')]
        z = z[order(z$pos, decreasing=T),]
        stop = z[!is.na(z$group) & !duplicated(z$group), c('chr', 'stop', 'group')]
        gr = merge(start, stop)
        gr = gr[order(gr$group),]
        ### compute number and percentage of samples
        num.pct.samples = computePCT.samples(z, gr)
        #z = z[order(z$pct.samples, decreasing=T),]
        #z = z[!is.na(z$group) & !duplicated(z$group),]
        gr = merge(gr, num.pct.samples, sort =F)
        #gr = merge(gr, z[, c('group', 'num.samples','pct.samples', 'sample')])
        gr = gr[, c('chr', 'start', 'stop', 'group', 'num.samples', 'pct.samples','sample')]
    }

    return(list(x=x, group=gr))
}
################################################################################################

######################### FUNCTION TO GENERATE UCSC CUSTOM TRACKS ##############################
custom.tracks <- function(x){
    peaks.for.ucsc = x[, c('chr','start','stop', 'pct.samples')]
    colnames(peaks.for.ucsc) = c('#chr','start','stop', 'pct.samples')
    min.value = min(peaks.for.ucsc$start)
    max.value = max(peaks.for.ucsc$stop)
    track.descp = paste0("Percentage of SV samples for peaks identified on ", chr)

    file.header = paste0("browser position ",chr,":",min.value,"-",max.value,"\ntrack type=bedGraph name=\"",chr,"\" description=\"",track.descp,"\" visibility=2 color=67,162,202")
    tmp = paste0(out.dir, '/ucsc_custom_track_files/', chr, '.bedGraph')
    cat( file.header, "\n", file = tmp)  
    write.table(peaks.for.ucsc, file = tmp, append = TRUE, row.names = FALSE, quote = F, sep="\t", col.names = F)
}
################################################################################################


###### call peaks for each chr for chosen svtype and plot results
out.dir <- paste0(out.dir,'/peaks')
dir.create(out.dir, showWarnings = FALSE)
dir.create(paste0(out.dir,'/ucsc_custom_track_files'), showWarnings = FALSE )

for (chr in chr.names.found){
    cat(chr, '\n')
    x = counts[counts$chr == chr & counts$svtype == svtype,]
    x = x[order(x$pos),]

    ### call peaks using peakPick algorithm
    h <- pp(x)
    x$peak = F
    x$peak[which(h[,2])] = T
    x$peak[x$pct.samples < pct.samples.cutoff] = F
    
    ### check if there were any peaks identified, otherwise skip 
    if (length(x$peak[x$peak])==0) {
      next 
    }
    
    ### call peaks using percentage of samples cutoff
    #x$peak = F
    #x$peak[x$pct.samples >= pct.samples.cutoff] = T

    ### call peaks using smoothed z-score method
    #lag       <- 1000
    #threshold <- 5
    #influence <- 0
    #result <- ThresholdingAlgo(x$pct.samples,lag,threshold,influence)
    #x$peak = F
    #x$peak[which(result$signals==1)] = T
    #x$peak[x$pct.samples < pct.samples.cutoff] = F

    ### group nearby peaks 
    z = groupPeaks(x, distance)
   
    ### write the results of the current chromosome
    write.table(z$group, file=paste0(out.dir, '/', chr, '.peak.group.bed'), sep='\t', quote=F, row.names=F)
    write.table(z$x, file=paste0(out.dir, '/', chr, '.peak.bed'), sep='\t', quote=F, row.names=F)

    ### generate UCSC custom tracks (create bedGraph files)
    if (!is.null(z$group) ) {
       custom.tracks(z$group)
    }

    ### plotting the peaks of the current chromosome
    ### extract genes located on the current chromsome from the list of genes of interest 
    if (genes.of.int !=0) {
      genes.in.chr = genes.of.interes[genes.of.interes$chr == chr,]
    } else {
      ### make fake line 
      genes.in.chr = data.frame(chr=chr, pos=-1000, gene='', stringsAsFactors=F)
      
    }
    genes.in.chr$y = -2
    
    ### plot the top panel (percentage of samples per window)
    x2 = counts[counts$chr == chr & counts$svtype != "ALL",]
    p1 = (ggplot(x2[x2$pct.samples > 0,], aes(x=pos, y=pct.samples, fill=svtype))
          + geom_bar(stat='identity', size=1)
          + theme_bw() + labs(x="", y="Percentage of samples (%)")
          + theme (plot.title=element_text(size=14, hjust=0.5, face="bold"),
                   axis.title.y=element_text(size=10, color="black"),
                   legend.position="top", legend.title=element_text(size=10, face="bold"))
          + ggtitle(paste('Percentage of samples across', chr, 'segments (windows)'))
          + scale_fill_manual(name="SV Type:", values=c('BND'='#2ca25f','INS'='#fec44f', 'INV'='#c994c7', 'DUP'='#b53f4d', 'DEL'='#2c7fb8', 'NC'='gray80'))
          + scale_x_continuous(labels = scales::comma, limits=c(0,max(x$pos)))
          + scale_y_continuous(limits=c(0, max(x2$pct.samples)+10), breaks=seq(0,100,10))
    )
    if (is.null(z$group)){#no peak or peak groups
        p2 = (ggplot(genes.in.chr)
                + geom_text(data=genes.in.chr, aes(x=pos, y=y, label=gene), angle=90, hjust=1,color='blue', size=1.5)
                + scale_x_continuous(labels = scales::comma, limits=c(0,max(x$pos)))
                + scale_y_continuous(limits=c(-10, max(x$pct.samples)+10), breaks=seq(0,100,10))
                + theme_bw()
                + ggtitle(paste0('Identified peaks (hotspots) on ', chr, ' (cutoff = ',pct.samples.cutoff,'%)'))
                + labs(x="Genomic position (bp)", y="Percentage of samples (%)")
                + theme (plot.title=element_text(size=14, hjust=0.5, face="bold"),axis.title.y=element_text(size=10, color="black"))
        )
    }else{
        p2 = (ggplot(x[x$peak,], aes(x=pos, y=pct.samples))
                + geom_bar(stat='identity', size=0, color='orange2', fill='orange2')
                + geom_point(shape=1, size=0.5, alpha=0.5, color="#2c7fb8")
                + theme_bw() + labs(x="Genomic position (bp)", y="Percentage of samples (%)")
                + geom_text(data=genes.in.chr, aes(x=pos, y=y, label=gene), angle=90, hjust=1,color='black', size=1.5, fontface="bold")
                #+ geom_segment(data=z$group, aes(x=start, y=(pct.samples+5), xend=stop, yend=(pct.samples+5)), color='blue')
                #+ geom_text(data=z$group, aes(x=(start+stop)/2, y=(pct.samples+7), label=group), size=2, color='blue', angle=90, hjust=0)
                + geom_hline (yintercept = pct.samples.cutoff , color='red', linetype='dashed', alpha=0.5)
                + annotate(geom="text", x=0, y=pct.samples.cutoff+1, label=paste0(pct.samples.cutoff,"%"),color="red", size=3)
                + scale_x_continuous(labels = scales::comma, limits=c(0,max(x$pos)))
                + scale_y_continuous(limits=c(-10, max(x$pct.samples)+10), breaks=seq(0,100,10))
                #+ggtitle(paste0('Identified peaks (hotspots) on ', chr, ' (cutoff = ',pct.samples.cutoff,'%)'))
                + ggtitle(paste0('Identified peaks (hotspots) on ', chr))
                + theme (plot.title=element_text(size=14, hjust=0.5, face="bold"),axis.title.y=element_text(size=10, color="black"))
        )
    }

    png(paste0(out.dir, '/', chr, '.png'), units='in', width=10, height=5, res=200)
    grid.arrange(p1,p2,nrow=2)
    dev.off()

}


