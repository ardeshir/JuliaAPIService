# Use the official Julia image as a parent image  
FROM julia:latest  
  
# Set the working directory in the container  
WORKDIR /usr/src/app  
  
# Copy the current directory contents into the container at /usr/src/app  
COPY . .  
  
# Install dependencies  
RUN julia -e 'using Pkg; Pkg.add(["HTTP", "JSON3", "DataFrames" \
    "JuMP", "HiGHS", "MathOptInterface", "Pkg", "Dates", "CSV", "DataStructures"])'   
  
# Run server.jl when the container launches  
CMD ["julia", "server.jl"]  
