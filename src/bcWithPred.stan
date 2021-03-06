data {
  int<lower=1> n; // number of field data
  int<lower=1> m; // number of computer simulation
  int<lower=1> n_pred; // number of predictions
  int<lower=1> p; // number of observable inputs x
  int<lower=1> q; // number of calibration parameters t
  vector[n] y; // field observations
  vector[m] eta; // output of computer simulations
  row_vector[p] xf[n]; // observable inputs corresponding to y
  // (xc, tc): design points corresponding to eta
  row_vector[p] xc[m]; 
  row_vector[q] tc[m]; 
  row_vector[p] x_pred[n_pred]; 
}

transformed data {
  real delta = 1e-9;
  int<lower = 1> N;
  vector[n+m] y_eta;
  vector[n+m+n_pred] mu; // mean vector
  row_vector[p] X[n+n_pred]; // X=[xf, x_pred]
  
  N = n + m + n_pred;
  // set mean vector to zero
  for (i in 1:N) {
    mu[i] = 0;
  }
  X[1:n] = xf;
  X[n+1:(n+n_pred)] = x_pred;
  y_eta = append_row(y, eta); // y_eta = [y, eta]
}

parameters {
  // tf: calibration parameters
  // rho_eta: reparameterization of beta_eta
  // rho_delta: reparameterization of beta_delta
  // lambda_eta: precision parameter for eta
  // lambda_delta: precision parameter for bias term
  // lambda_e: precision parameter of observation error
  // y_pred: predictions
  row_vector<lower=0, upper=1>[q] tf; 
  row_vector<lower=0, upper=1>[p+q] rho_eta; 
  row_vector<lower=0, upper=1>[p] rho_delta; 
  real<lower=0> lambda_eta; 
  real<lower=0> lambda_delta;
  real<lower=0> lambda_e; 
  vector[n_pred] y_pred; 
}

transformed parameters {
  // beta_delta: correlation parameter for bias term
  // beta_e: correlation parameter of observation error
  row_vector[p+q] beta_eta;
  row_vector[p] beta_delta; 
  beta_eta = -4.0 * log(rho_eta);
  beta_delta = -4.0 * log(rho_delta);
}

model {
  // declare variables
  vector[N] z; // z = [y, eta, y_pred]
  matrix[N, N] sigma_eta; // simulator covarinace
  matrix[n+n_pred, n+n_pred] sigma_delta; // bias term covariance
  matrix[N, N] sigma_z; // covariance matrix
  matrix[N, N] L; // cholesky decomposition of covariance matrix 
  row_vector[p] temp_delta;
  row_vector[p+q] temp_eta;
  row_vector[p+q] xt[N];
  
  z = append_row(y_eta, y_pred); // z = [y, eta, y_pred]

  // xt = [[xf,tf],[xc,tc],[x_pred,tf]]
  for (i in 1:n) {
    xt[i] = append_col(xf[i],tf);
  }
  for (i in (n+1):(n+m)) {
    xt[i] = append_col(xc[i-n],tc[i-n]);
  }
  for (i in (n+m+1):N) {
    xt[i] = append_col(x_pred[i-n-m],tf);
  }
  
  // elements of sigma_eta
  for (i in 1:(N-1)) {
	sigma_eta[i, i] = 1/lambda_eta + delta;
    for (j in (i+1):N) {
	  sigma_eta[i, j] = exp(-dot_self((xt[i] - xt[j]) .* beta_eta))/lambda_eta;
      sigma_eta[j, i] = sigma_eta[i, j];
    }
  }
  sigma_eta[N, N] = 1/lambda_eta + delta;
  
  // elements of sigma_delta and add observation errors
  for (i in 1:(n+n_pred-1)) {
	sigma_delta[i, i] = 1/lambda_delta;
    for (j in (i+1):n+n_pred) {
	  sigma_delta[i, j] = exp(-dot_self((X[i] - X[j]) .* beta_delta))/lambda_delta;
      sigma_delta[j, i] = sigma_delta[i, j];
    }
  }
  sigma_delta[n+n_pred, n+n_pred] = 1/lambda_delta;

  // computation of covariance matrix sigma_z 
  sigma_z = sigma_eta;
  sigma_z[1:n, 1:n] = sigma_eta[1:n, 1:n] + 
    sigma_delta[1:n, 1:n];
  sigma_z[1:n, (n+m+1):N] = sigma_eta[1:n, (n+m+1):N] + 
    sigma_delta[1:n, (n+1):(n+n_pred)];
  sigma_z[(n+m+1):N, 1:n] = sigma_eta[(n+m+1):N, 1:n] + 
    sigma_delta[(n+1):(n+n_pred),1:n];
  sigma_z[(n+m+1):N, (n+m+1):N] = sigma_eta[(n+m+1):N, (n+m+1):N] + 
    sigma_delta[(n+1):(n+n_pred), (n+1):(n+n_pred)];

  // add observation errors
  for (i in 1:n) {
    sigma_z[i, i] = sigma_z[i, i] + (1 / lambda_e);
  }  

  // Specify priors here
  rho_eta ~ beta(1.0, 0.3);
  rho_delta ~ beta(1.0, 0.3);
  lambda_eta ~ gamma(10, 10); // gamma (shape, rate)
  lambda_delta ~ gamma(10, 0.3); 
  lambda_e ~ gamma(10, 0.03); 

  L = cholesky_decompose(sigma_z); // cholesky decomposition 
  z ~ multi_normal_cholesky(mu, L);
}
