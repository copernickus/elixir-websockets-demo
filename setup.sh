#!/bin/sh
echo "Updating submodules ..."
git submodule update --init

echo "Compiling misultin ..."
cd deps/misultin && make

echo "Compiling elixir ..."
cd ../../deps/elixir && make test

echo "All compiled. If the tests above fail, please open an issue in Elixir's issues tracker on Github"