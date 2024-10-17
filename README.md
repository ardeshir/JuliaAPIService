# Julia API Service

### Step 1: Install Docker
Make sure Docker is installed on your machine. You can download and install Docker from the official Docker website.

### Step 2: Create a Dockerfile
Ensure you have a Dockerfile in your current working directory. Here’s a simple example of a Dockerfile:

```docker
# Use the latest version of the Julia image from Docker Hub as the base image
FROM julia:1.11.0

# Create a new user named 'jl' with a home directory and bash shell
# Note: using a custom user to run our application instead of root results in better security
RUN useradd --create-home --shell /bin/bash jl

# Create a directory for the application in the 'jl' user's home directory
RUN mkdir /home/jl/app

# Set the working directory to the app directory
WORKDIR /home/jl/app

# Change the ownership of the home directory to the 'jl' user and group
RUN chown -R jl:jl /home/jl/

# Switch to the 'jl' user for running subsequent commands
USER jl

# Copy the project dependency file app directory in the container
# Note: Copying this file and installing the dependencies before the rest of the code results in faster build times in subsequent builds
COPY Project.toml .

# Run a Julia command to set up the project: activate the project and instantiate to download its dependencies
RUN julia --project -e "using Pkg; Pkg.instantiate();"

# Also can use 
# RUN julia -e 'using Pkg; Pkg.add.(["CSV", "DataFrames", "Dates", "JSON"])'

# Copy the current directory's contents into the working directory in the container
COPY . .

# Precompile project's code and dependencies
RUN julia --project -e "using Pkg; Pkg.precompile();"

# Inform Docker that the container listens on ports 8000 at runtime
EXPOSE 8000

# Set environment variables used by Julia and the Genie app
# JULIA_DEPOT_PATH  - Path to Julia packages
# JULIA_REVISE      - Disable the Revise package to speed up startup
# EARLYBIND         - Enable early binding for performance improvements
ENV JULIA_DEPOT_PATH "/home/jl/.julia"
ENV JULIA_REVISE "off"
ENV EARLYBIND "true"

# Define the command to run the Genie app when the container starts
CMD ["julia", "--project", "model.jl"]

```

### Step 3: Build the Docker Image
Navigate to the directory containing your Dockerfile and run the following command to build the Docker image. Replace yourusername with your Docker Hub username and yourimagename with the name you want to give your image.

` docker build -t yourusername/yourimagename . ` 
 

### Step 4: Tag the Docker Image
Tagging is often done to differentiate versions of the image. Here, we'll tag the image with latest. You can also tag it with a version number like v1.0.

` docker tag yourusername/yourimagename yourusername/yourimagename:latest  `
 

### Step 5: Log in to Docker Hub
Log in to your Docker Hub account using the following command:

` docker login ` 
 
You will be prompted to enter your Docker Hub username and password.

Step 6: Push the Docker Image to Docker Hub
Push your image to Docker Hub using the following command:

` docker push yourusername/yourimagename:latest ` 
 

### Step 7: Verify the Image on Docker Hub
Go to Docker Hub and navigate to your repository to verify that the image has been uploaded successfully.

## Full Command Summary
Here’s a summary of all the commands you need to run:

Build the Docker image:
`docker build -t yourusername/yourimagename . `
 
2. Tag the Docker image:
`docker tag yourusername/yourimagename yourusername/yourimagename:latest `

3. Log in to Docker Hub:
` docker login `

4. Push the Docker image to Docker Hub:
` docker push yourusername/yourimagename:latest `

# Building Web APIs with HTTP

- Docs: [https://github.com/JuliaWeb/HTTP.jl](HTTP)

See src/Service.jl for an example API service 