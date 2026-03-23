# SaG4n docker image revertex

This is a docker image for SaG4n, a tool for generating neutrons and gammas from (alpha,n) reactions.
This image was generated to be used with the [revertex](https://github.com/legend-exp/revertex) primary generator for the [remage](https://github.com/legend-exp/remage) Geant4 framework.

## Usage

Assuming the input and output files lie in or below the current working directory, the image can be run with the following command:

```bash
sudo docker run --rm \
        -u $(id -u):$(id -g) \
        -v "$PWD:$PWD" \
        -w "$PWD" \
        sag4n:latest \
        [input_file]
```

where `[input_file]` is the path to the input file for SaG4n.