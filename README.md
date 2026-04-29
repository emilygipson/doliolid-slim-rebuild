# doliolid-slim-rebuild

SLiM forward simulations for *Dolioletta gegenbauri* mitogenome population genetics. Rebuilt from the ground up to test whether the empirical Tajima's D in this species reflects purifying selection on the non-recombining mitogenome rather than demographic expansion.

## Model features

- nonWF model with obligate alternation of sexual and asexual reproduction
- Haploid mitochondrial chromosome
- Mutation rate calibration to empirical nucleotide diversity
- Parameter sweeps across new life cycle combinations and empirical anchors
- Purifying selection with per-gene DFE based on empirical dN/dS

## Repository structure

```
doliolid-slim-rebuild/
├── scripts/
│   ├── slim/       # SLiM simulation scripts
│   └── bash/       # SLURM job submission wrappers
└── params/         # Parameter files
```

## Software

| Tool | Purpose |
|------|---------|
| SLiM 5.1 | Forward genetic simulations |
