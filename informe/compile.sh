#!/bin/bash
# Script para compilar el informe LaTeX a PDF usando podman

cd "$(dirname "$0")"

echo "Compilando informe.tex a informe.pdf..."
podman run --rm -v ".:/workdir:Z" -w /workdir registry.gitlab.com/islandoftex/images/texlive:latest xelatex -interaction=nonstopmode informe.tex
podman run --rm -v ".:/workdir:Z" -w /workdir registry.gitlab.com/islandoftex/images/texlive:latest xelatex -interaction=nonstopmode informe.tex

echo "Listo. Archivo generado: informe.pdf"
