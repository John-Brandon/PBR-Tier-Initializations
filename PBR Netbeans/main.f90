program main        
!#######################################################    
! File:     main.f
! Author:   John R. Brandon
! Contact:  jbrandon at gmail             
! Date:     Summer 2015
! Purpose:  Run PBR Tier System simulations            
!#######################################################              
! Modules of code contain: subroutines, functions and possibly variable / format declarations.
!  Each module of code is contained in a separate file (e.g. Declare_variables_module.f90).
!  The code in each module file needs to be compiled and linked with the compiled main program to produce an executable.
!  Note: The order in which these modules are compiled relative to the main program may matter. (using the gfortran compiler, at least) 
!   Assume that the modules need to be compiled before they are linked with the main program to form an executable. 
!
!   This can be done in one line from the shell prompt (denoted by $). Note the file order in the command-line example below:
!    $ gfortran module1.f90 module2.f90 main.f -o desired_executable_name_here
!
!   Whereas, this shell command might not link properly, because the main program is compiled before module2.f90:
!    $ gfortran module1.f90 main.f module2.f90 -o desired_executable_name_here
!             
!   This can be a source of maddening errors during compiling if you're developing code in an integrated development environment (IDE). 
!   As an example, using NetBeans IDE 8.0.2 under Mac OS 10.9.5, whether or not the first letter of the file name 
!     is upper or lower case splits a tie in alphabetic file order (e.g. "Module2.f90" is linked before "module1.f90").             
!    
!   If you can't get things to compile and link in an IDE (e.g. 'Error can't find .mod file') you can try and figure out the settings the IDE
!    uses when ordering its list of files to the Fortran compiler, and then change those settings to make sure the module files are compiled in proper order before linking. 
!    Alternatively, you can use the shell prompt to manually control the correct order of file compilation (as in the first $ example above).              
!#######################################################
!   General comments:
!   (i) At present, the population dynamics model assumes this order for entering female adult-hood: 
!       (1st) Maturity (ovulation) on her a_m'th birthday -> (2nd) Adult mortality rate applied during her a_m'th year -> (3rd) First partuition (one year after her a_m'th birthday, if she survives that first year of adult-hood).
!         (a) a_m is the age at which females mature (males are assumed to be a non-limiting factor for reproduction / birth rates)
!         (b) The code for the population dynamics model would need to be revised to take into account reproductive senescence (as might be expected for at least some "black-fish", e.g. killer whales).
!         (c) Gestation length after reaching a_m is assumed to be one year. TODO: make sure birth rates bounded between 0.0 and 1.0 
!   (ii)             
!#######################################################
    use Declare_variables_module       ! Declares global variables accessible by the main program here: Declare_variables_module.f90
    use PBR_FileIO_Module              ! Reading initial values from files, and for writing output : PBR_FileIO_Module.f90
    use initialize_pop                 ! Initialization of life history and age structure : Initialize_pop_module.f90
    use calcs                          ! Routines for various calculations (e.g. calculating N_min) : PBRmodule.f
    use random, only : random_normal   ! Routines for psuedo random number generators (RNG) -- only using random_normal() function at this stage : Random_module.f90
    use Generate_random_numbers_module ! Determine if seed for RNG is user defined (for reproducible results) or if seed is based on CPU clock (for different psuedo random variates each time program runs): Generate_random_numbers_module.f90
    use PBR_Errorcheck_module          ! Contains function 'error_check_input' to do error checking on input values [Very Beta]
    use eigen_module                   ! Contains calls to DGEEV for calculating the eigenvalues and eigenvectors of the projection matrix
!====== +++ === === +++ === === +++ === ! Turns off implicit typing by Fortran; all variables must be explicitly declared by type
    implicit none 
!====== +++ === === +++ === === +++ ===                 ! Constant parameters
    integer(kind = 4), parameter :: stock_1 = 1         ! Indexes for stock structure array
    integer(kind = 4), parameter :: stock_2 = 2         ! TODO? Move parameters into Main_pars_module?
    integer(kind = 4), parameter :: all_areas = 0
    integer(kind = 4), parameter :: area_1 = 1
    integer(kind = 4), parameter :: area_2 = 2
    integer(kind = 4), parameter :: area_3 = 3    
    integer(kind = 4), parameter :: area_4 = 4 
    integer(kind = 4), parameter :: n_area = 4          ! Counter for do loops
    integer(kind = 4), parameter :: female = 1          
    integer(kind = 4), parameter :: male = 2            ! TODO ?: Move this list of variable declarations into a module (e.g. main_vars_module)
!====== +++ === === +++ === === +++ ===                 ! Local variables 
    real(kind = 8), allocatable :: f_init_ii(:)         ! Initial human caused mortality rates for each stock  
    real(kind = 8), allocatable :: f_yr_stock(:,:)      ! Human caused mortality rate each year (rows) by stock (columns)
    real(kind = 8), allocatable :: b_init_ii(:)         ! Initial birth rate for each stock 
    real(kind = 8), allocatable :: b_yr_stock(:,:)      ! Birth rate each year (rows) by stock (columns)    
    real(kind = 8), allocatable :: depl_yr_stock(:,:) ! Depletion each year (rows) by stock (columns)
    real(kind = 8), allocatable :: transition_matrix_tmp(:, :) ! Tmp matrix to pass to eigen function (is changed by eigen on return)
    real(kind = 8), allocatable :: movement_matrix(:, :, :) ! rows = ages x cols = areas x stock. Values = proportion of stock in each area
! Array of numbers-at-sex and age for each stock in each sub-area by year of projection        
    real(kind = 8), allocatable :: N_age_sex_area_stock_yr_sim(:,:,:,:,:,:)  ! Main pop array: age, sex, sub-area, stock, yr & simulation  
    real(kind = 8), allocatable :: N_tot_sex_area_stock_yr_sim(:, :, :, :, :)
    real(kind = 8), allocatable :: area_stock_prop(:,:)    ! Percentage of each stock in each area
    real(kind = 8), allocatable :: eigv(:)                 ! Eigen vector of transition matrix, e.g. returned by power_method()
    integer(kind = 4), allocatable :: is_surv_yr( : )  ! Matrix containing 1s if element is survey year, zeros otherwise
    real(kind = 8), allocatable :: n_hat_yr_sim(:, :)         ! Estimate of abundance each year
    real(kind = 8), allocatable :: foo_vector(:)       ! DEBUGGING
    real(kind = 8), allocatable :: N_plus_area123(:, :, :) ! Total age 1+ abundance in the survey area, by stock and simulation.  
    real(kind = 8), allocatable :: N_tot_area123(:, :, :)  ! Total (age 0+) abundance in the survey area, by stock and simulation.
    real(kind = 8), allocatable :: pbr_yr_sim(:, :)    ! PBR by year and simulation
    real(kind = 8), allocatable :: M_yr_sim(:, :)      ! Realized human caused mortality each year ~N(mu = PBR, sigma = CV_mortality * PBR)
    real(kind = 8), allocatable :: sigma_pbr_yr_sim(:, :) ! Standard deviation of human caused mortality (given PBR and CV_Mortality)
    real(kind = 8), allocatable :: selectivity_norm(:) ! Standardized selectivity at age: selectivity(age) / sum(selectivity(age))
    real(kind = 8) :: NPR_mature                       ! Numbers mature per female recruit. Used to calculate b_eq (birth rate at K)
    real(kind = 8) :: objf_lambda                      ! Objective function for finding juvenile survival that results in R_max
    real(kind = 8) :: objf_f_init                      ! Objective function for finding f_init resulting in stable age structure
    real(kind = 8) :: brent    ! Function brent() :: file = Brent.f90 (TODO? : Create and add this to a Roots_and_Mins_module.f90)
    real(kind = 8) :: lambda                            ! Dominant real eigen value of the transition matrix
    integer(kind = 4) :: io_error                       ! Error flag for checking initial values in input.par
    integer(kind = 4) :: sim_ii, ii, jj, aa, ss, yr     ! Counters for indexing loops  
    real(kind = 8) :: foo, foo1, foo2                  ! DEBUGGING    
!    integer(kind = 4) :: it_num                         ! Iteration number returned from power_method() for calculating lambda
!    character(len = 10) :: stock_name                   ! For printing output tables
!====== +++ === === +++ === === +++ === ! Read initial values and do error checking
    call read_inits()              ! Read initial values from 'input.par' file. PBR_FileIO_Module contains subroutine 'read_inits()' 
    io_error = 0                   ! Check for input value errors (values out of bounds, etc) 
    io_error = error_check_input() ! Function that contains error checking code. Located in file: PBR_Errorcheck_module.f90
    if(io_error .ne. 0) then       ! Check error code
        print *, "Error Code: ", io_error  ! If error, print code
        stop                       ! If error, exit program
    end if                         ! TODO? Move this error checking to be called at the end of read_inits() procedure? 
!====== +++ === === +++ === === +++ === ! Given input, allocate array dimensions at run-time (local variables)
    allocate(f_init_ii(1:n_stocks))     ! Stock specific initial human caused mortality rates (can have stock specific init_depl's)
    allocate(f_yr_stock(0:yr_max, 1:n_stocks)) ! Human caused mortality rate each year (rows) by stock (columns)
    allocate(b_init_ii(1:n_stocks))        ! Stock specific initial birth rate, given stock specific initial depletion levels
    allocate(b_yr_stock(0:yr_max, 1:n_stocks)) ! Birth rate each year (rows) by stock (columns)
    allocate(depl_yr_stock(0:yr_max, 1:n_stocks)) ! Depletion each year (rows) by stock (columns)
    allocate(N_age_sex_area_stock_yr_sim(0:age_x, 1:2, 0:4, 1:n_stocks, 0:yr_max, 0:n_sims)) ! Main pop array, sim = 0 is reference case with no mortality    
    allocate(N_tot_sex_area_stock_yr_sim(1:2, 1:n_area, 1:n_stocks, 0:yr_max, 0:n_sims)) ! 
    allocate(area_stock_prop(1:4, 1:n_stocks))  ! TODO: Hard-coded four areas here - TODO: soft-code
    allocate(transition_matrix(0:age_x, 0:age_x))! Transition matrix, added here while developing methods for population projections and solving for juvenile survival (given lamda_max)
    allocate(transition_matrix_tmp(0:age_x, 0:age_x)) ! Place-holder for transition matrix. Gets sent to eigen and is changed on return
    allocate(movement_matrix(0:age_x, 0:n_area, 0:n_stocks))
    allocate(N_plus_area123(0:yr_max, 0:n_stocks, 0:n_sims)) ! Total age 1+ abundance in the survey area, by stock and simulation. Stock = 0 will hold the sum of both stocks.  
    allocate(N_tot_area123(0:yr_max, 0:n_stocks, 0:n_sims))  ! Total (age 0+) abundance in the survey area, by stock and simulation. Stock = 0 will hold the sum of both stocks.   
    allocate(pbr_yr_sim(0:yr_max, 0:n_sims))     ! PBR each year
    allocate(M_yr_sim(0:yr_max, 0:n_sims))     ! Realized human caused mortality each year ~N(mu = PBR, sigma = CV_mortality * PBR)
    allocate(sigma_pbr_yr_sim(0:yr_max, 0:n_sims))
    allocate(selectivity_norm(0:age_x)) ! Selectivity at age, standardized so that the vector sums to 1.0
    allocate(eigv(0:age_x))        ! Eigen vector of transition matrix, returned by power_method()  
    allocate(is_surv_yr(0:yr_max)) ! Matrix containing 1s if element is survey year, zeros otherwise 
    allocate(n_hat_yr_sim(0:yr_max, 0:n_sims))   ! Abundance estimates
    allocate(N_min_yr_sim(0:yr_max, 0:n_sims))
    
    allocate(S_age(0:age_x))       ! Survival at age vector
    allocate(prop_mat_age(0:age_x))! Proportion mature at age
    allocate(selectivity(0:age_x)) ! Selectivity at age -- currently assuming knife-edge selectivity at age a_r (same selectivity for each stock)
    allocate(NPR_age(0:age_x))     ! Numbers at age per recruit vector
    allocate(NPR_age_tmp(0:age_x)) ! Numbers at age per recruit vector, used to solve for initial human caused mortality rate 
! These three below are assigned in calc_NPR_age(), but currently not utilized    
    allocate(prop_NPR(0:age_x))    ! Rescaled numbers at age per recruit vector (sums to 1.0 over ages)
    allocate(Nage_imm_0(0:age_x))  ! Immature numbers at age vector
    allocate(Nage_mat_0(0:age_x))  ! Mature numbers at age vector
    allocate(N_age(0:age_x))       ! Numbers at age vector    
    allocate(N_plus(0:yr_max))     ! Vector of age 1+ population size over projection years -- summed across stocks in survey area
    allocate(N_tot(0:yr_max))      ! Total (0+) population size each year of projection -- summed across stocks in survey area
    allocate(N_calf(0:yr_max))     ! Vector of calf production for each projection year -- summed across stocks in survey area
    allocate(Female_age(0:age_x))  ! Females at age vector -- summed across stocks in survey area
    allocate(Male_age(0:age_x))    ! Males at age vector -- summed across stocks in survey area
    allocate(foo_vector(0:age_x))  ! DEBUGGING
!   allocate(NPR_age_ii(0:age_x, 1:n_stocks))      ! Numbers at age per female recruit (row) for stock i (column)
!   allocate(NPR_oneplus_ii(1:n_stocks))           ! Total number of age 1+ per female recruit for stock i 
!====== +++ === === +++ === === +++ === ! Initialize those variables declared in Declare_variables_module -- set to zero.
    Call initialize_global_vars()       ! Does not initialize (i.e. overwrite) those variables with values read from input.par file
!====== +++ === === +++ === === +++ === ! Initialize those variables declared in main program (above) -- set to zero.
    call initialize_local_vars()        ! This subroutine is contained in the main program (at bottom)
!====== +++ === === +++ === === +++ === ! Set seed for RNG -- see comment after 'use Generate_random_numbers_module' statement above
    Call set_random_seed() ! Set seed based on input.par, either: (a) given # (reproducible results), or (b) based on CPU clock
!====== +++ === === +++ === === +++ === ! Initialize vectors: survival, selectivity and proportion mature at age   
    Call assign_par_vectors(a_r, a_m, a_t, age_x, s_adult, s_juv, &  
                            S_age, selectivity, prop_mat_age) ! Currently these three vectors are identical for each stock  
!====== +++ === === +++ === === +++ === ! Solve for juvenile survival rate that results in specified r_max
    transition_matrix(:,:) = 0.0d0       ! Need to initialize this matrix to zero, because evidently, if we don't, LAPACK(?) is not nice.
! Specifically, I (JRB) had horrible buggy trouble with Mac OS X's 'accelerate' framework (LAPACK library call to function DGEEV).    
    fecundity_max = b_max * b_sex_ratio  ! Define fecundity in terms of female calves per female for eigen analysis of matrix
! Assign non-zero values to transition matrix    
    transition_matrix = assign_transition_matrix(a_m, a_t, age_x, fecundity_max, S_age, prop_mat_age) 
    print *,
    print *, "Initial transition matrix: "  ! Check
    do aa = 0, age_x        
        write (*, "(400f8.3)") (transition_matrix(aa, jj), jj = 0, age_x)    
! The 400f... is a bit of a hack. Works if <= 400 columns, age / stage classes to be printed 
    end do
!====== +++ === === +++ === ===  ! Test LAPACK procedure DGEEV for finding eigenvalues and eigenvectors of real nonsymetric matrix
    transition_matrix_tmp = transition_matrix ! Assign transition matrix to temp matrix, destroyed on return from eigen()
    print *, "Calling eigen() for initial transition matrix: "
    call eigen(transition_matrix_tmp, (age_x + 1), lambda) ! Calculate Lambda_max for input life history values: s_juv, etc.
    print *, "Initial lambda: ", lambda
!====== +++ === === +++ === === +++ === ! Solve for juvenile survival rate that corresponds with the user specified lambda_max
    objf_lambda = BRENT(ax = 0.01d0, bx = 0.98d0, cx = 0.99d0, func = calc_lambda, & ! See Brent.f90 for details on arguments
                            tol = 0.0000001d0, xmin = s_juv)                         ! Note calc_lambda() assigns projection matrix
    print *, "objf_lambda: ", objf_lambda ! Check, should be very close to "tol", i.e. nearly zero within machine precision
    print *, "Solution for juvenile survival: ", s_juv    ! Check
!====== +++ === === +++ === === +++ === ! Initialize vectors: survival, selectivity and proportion mature at age   
    Call assign_par_vectors(a_r, a_m, a_t, age_x, s_adult, s_juv, &  ! Slightly repetitious, but need to re-assign s_juv rates
                            S_age, selectivity, prop_mat_age)        ! Currently these three vectors are identical for each stock   
!====== +++ === === +++ === === +++ === ! Re-assign s_juv (etc) to transition matrix and output for checking
    transition_matrix = assign_transition_matrix(a_m, a_t, age_x, b_max, S_age, prop_mat_age) ! Assign non-zero values to transition matrix
    print *, "New transition matrix: "
    do aa = 0, age_x ! Print the transition matrix with lambda_max = 1.04 (Check above) to the screen
        write (*, "(400f8.3)") (transition_matrix(aa, jj), jj = 0, age_x) ! The 400f format is a hack. Works if <= 400 columns to be printed
    end do
    print *, ""
!====== +++ === === +++ === === +++ === ! Assign values to the matrix with percentage of each stock in each area 
    area_stock_prop = assign_area_stock_prop(p_a1_s1, p_a2_s1, p_a2_s2, p_a3_s2, p_a4_s2) 
!====== +++ === === +++ === === +++ === ! Calculate Numbers per female recruit, with no human caused mortality (f_init = 0.0)
    Call calc_NPR_age(f_rate = 0.0d0, &                        ! d0 suffix for double precision to match argument type in function                                             
        N_recruits = b_sex_ratio, N_age_tmp = NPR_age, &       ! Calc NPR_age, NPR_oneplus and NPR_mature (F = 0)
        sum_1plus = NPR_oneplus, sum_mature = NPR_mature) 
    print *, "Finished calling, calc_NPR_age(): " 
    print *, "NPR_age :", NPR_age
!====== +++ === === +++ === === +++ === ! Calculate equilibrium birth rate (at carrying capacity)
    b_eq = 1 / NPR_mature               ! Equilibrium birth rate. Equal for both stocks under assumption of identical life histories                
!====== +++ === === +++ === === +++ === ! Calculate the initial age structure and distribute across areas for each stock         
! TODO?? : Move this loop into a subroutine in Initialize_pop_module 
    do ii = 1, n_stocks                 ! Initial age structures for each stock can differ, e.g. initial depletion may not be equal
        init_depl_i = init_depl(ii)     ! New value for global variable init_depl_i. Used by Initial_F(), as called from brent()
        b_init = b_eq + (b_max - b_eq) * (1 - (init_depl_i ** theta))  ! Initial birth rate for stock i
        b_init_ii(ii) = b_init                                         ! Storing initial birth rates in vector by stock 
        b_yr_stock(0, ii) = b_init          ! Store initial birth rate 
        depl_yr_stock(0, ii) = init_depl_i  ! Store initial depletion level 
        prop_NPR = NPR_age / sum(NPR_age)   ! Proportion at age relative to numbers per female recruit

! Calculate initial human caused mortality rate (f_init) that results in stable age-structure at initial depletion                
        objf_f_init = BRENT(ax = 0.0d0, bx = 0.10d0, cx = 1.0d0, func = initial_F, & ! See Brent.f90 for details on arguments
                            tol = 0.0000001d0, xmin = f_init_ii(ii)) 
      
        Call rescale_NPR(k_1plus_tmp = k_1plus(ii), initial_oneplus_tmp = NPR_oneplus, & ! Scale NPR to Numbers at age
                        N_age_unscaled = NPR_age_tmp, N_age_scaled = N_age) ! N_age returned as scaled numbers of females at age 

!        do sim_ii = 0, n_sims ! Initial conditions are deterministic and hence identical across simulations. Make it so.
!            N_age_sex_area_stock_yr_sim(:, female, 0, ii, 0, sim_ii) = N_age  ! Assign scaled numbers at age for this stock to main array
!            N_age_sex_area_stock_yr_sim(:, male, 0, ii, 0, sim_ii) = N_age    ! Note: area = 0 represents the sum of numbers across all areas                        
!        end do
        
        do sim_ii = 0, n_sims ! Initial conditions are deterministic and hence identical across simulations. Make it so.
            
            N_age_sex_area_stock_yr_sim(:, female, 0, ii, 0, sim_ii) = N_age  ! Assign scaled numbers at age for this stock to main array
            N_age_sex_area_stock_yr_sim(:, male, 0, ii, 0, sim_ii) = N_age    ! Note: area = 0 represents the sum of numbers across all areas                        
            
            do jj = 1, n_area ! Allocate abundance across areas for each stock
                do ss = 1,2   ! males and females
                    
                    N_age_sex_area_stock_yr_sim( : , ss, jj, ii, 0, :) = &
                        N_age_sex_area_stock_yr_sim( : , ss, all_areas, ii, 0, :) * area_stock_prop(jj, ii)

                    N_tot_sex_area_stock_yr_sim(ss, jj, ii, 0, sim_ii) = & ! Get total abundance for each stock in each area
                        sum(N_age_sex_area_stock_yr_sim(0:age_x, ss, jj, ii, 0, sim_ii))
                        
                end do  ! End loop over sexes
            end do      ! End loop over areas
        end do          ! End loop over simulations
        
        N_plus_area123(0, ii, 0) = sum(N_age_sex_area_stock_yr_sim(1:age_x, 1:2, 1:3, ii, 0, 0)) ! yr, stock, sim
        N_tot_area123(0, ii, 0) = sum(N_age_sex_area_stock_yr_sim(0:age_x, 1:2, 1:3, ii, 0, 0))    ! get abundance in survey area for each stock 
        
    end do              ! end loop over stocks
!====== +++ === === +++ === === +++ === TODO: Move the operations below into the loop above
! TODO : Check the calculations above for N_tot_sex_area_stock_yr_sim(ss, jj, ii, 0, sim_ii), then delete this chunk of code     
!    do sim_ii = 0, n_sims 
!        do ii = 1, n_stocks   
!            do jj = 1, n_area ! Areas 
!                N_tot_sex_area_stock_yr_sim(female, jj, ii, 0, sim_ii) = &
!                    sum(N_age_sex_area_stock_yr_sim(0:age_x, female, jj, ii, 0, sim_ii))
!                N_tot_sex_area_stock_yr_sim(male, jj, ii, 0, sim_ii) = &
!                    sum(N_age_sex_area_stock_yr_sim(0:age_x, male, jj, ii, 0, sim_ii))
!            end do 
!        end do 
!    end do    
!====== +++ === === +++ === === +++ === Some final accounting in recording initial conditions
    N_plus(0) = sum(N_age_sex_area_stock_yr_sim(1:age_x, 1:2, 1:3, 1:n_stocks, 0, 0)) ! Sum across stocks, in the surveyed areas
    N_tot(0) = sum(N_age_sex_area_stock_yr_sim(0:age_x, 1:2, 1:3, 1:n_stocks, 0, 0))  ! These vectors might be redundant now, see below : TODO

    N_plus_area123(0, 0, 0) = sum(N_age_sex_area_stock_yr_sim(1:age_x, 1:2, 1:3, 1:n_stocks, 0, 0)) ! yr, stock, sim
    N_tot_area123(0, 0, 0) = sum(N_age_sex_area_stock_yr_sim(0:age_x, 1:2, 1:3, 1:n_stocks, 0, 0))
!====== +++ === === +++ === === +++ === Calculate standardized selectivity at age (selectivity_norm sums to one)
    selectivity_norm(:) = selectivity(:) / sum(selectivity(:))
!====== +++ === === +++ === === +++ === Do projections through time with no human caused mortality as reference case        
    do sim_ii = 0, n_sims ! The zero'th sim is the reference projection without any human caused mortality    
! Assign initial abundance from numbers at age for each simulation
      N_plus_area123(0, 0, sim_ii) = sum(N_age_sex_area_stock_yr_sim(1:age_x, 1:2, 1:3, 1:n_stocks, 0, sim_ii)) ! yr, stock, sim
      N_plus_area123(0, 1, sim_ii) = sum(N_age_sex_area_stock_yr_sim(1:age_x, 1:2, 1:3, 1, 0, sim_ii)) ! yr, stock, sim
      N_plus_area123(0, 2, sim_ii) = sum(N_age_sex_area_stock_yr_sim(1:age_x, 1:2, 1:3, 2, 0, sim_ii)) ! yr, stock, sim
      
      N_tot_area123(0, 0, sim_ii) = sum(N_age_sex_area_stock_yr_sim(0:age_x, 1:2, 1:3, 1:n_stocks, 0, sim_ii))  ! 
      N_tot_area123(0, 1, sim_ii) = sum(N_age_sex_area_stock_yr_sim(0:age_x, 1:2, 1:3, 1, 0, sim_ii))  ! get abundance in survey area for each stock
      N_tot_area123(0, 2, sim_ii) = sum(N_age_sex_area_stock_yr_sim(0:age_x, 1:2, 1:3, 2, 0, sim_ii))  ! get abundance in survey area for each stock
      
      do yr = 1, yr_max   ! Years -- starting at year one, because year zero is in the books and pop has been initialized
        
        do ii = 1, n_stocks ! Stocks            
            
            b_yr_stock(yr, ii) = b_eq + (b_max - b_eq) * (1 - depl_yr_stock(yr - 1, ii)**theta) ! Annual birth rate for each stock
            
            do jj = 1, n_area ! Areas
                
                do ss = 1, 2  ! Sexes
        
                    Call pop_projection(f_rate = 0.0d0, b_rate = b_yr_stock(yr, ii), & ! Project males and females separately,
                      N_age_old = N_age_sex_area_stock_yr_sim(:, ss, 0, ii, yr - 1, sim_ii),  &    !  because could potentially have different selectivities, 
                      N_age_new = N_age_sex_area_stock_yr_sim(:, ss, 0, ii, yr, sim_ii))           !  in a future version of operating model         
!                    Call pop_projection(f_rate = 0.0d0, b_rate = 0.50d0, &
!                      N_age_old = N_age_sex_area_stock_yr(:, ss, 0, ii, yr - 1),  &
!                      N_age_new = N_age_sex_area_stock_yr(:, ss, 0, ii, yr))                    
                      
!                    do aa = 0, age_x ! Ages (Don't think actually need to loop over ages, could just insert ":" in array 
                !! Anything needed here?       
                        N_age_sex_area_stock_yr_sim(:, ss, jj, ii, yr, sim_ii) = & ! Redistribute each stock (by age) across areas
                          N_age_sex_area_stock_yr_sim(:, ss, 0, ii, yr, sim_ii) * area_stock_prop(jj, ii)
!                    end do ! End loop over ages
                    
                    depl_yr_stock(yr, ii) = sum(N_age_sex_area_stock_yr_sim(1:age_x, :, 0, ii, yr, sim_ii)) / k_1plus(ii) ! In terms of ages 1+ 
                
                    N_tot_sex_area_stock_yr_sim(female, jj, ii, yr, sim_ii) = &
                        sum(N_age_sex_area_stock_yr_sim(0:age_x, female, jj, ii, yr, sim_ii))
                    N_tot_sex_area_stock_yr_sim(male, jj, ii, yr, sim_ii) = &
                        sum(N_age_sex_area_stock_yr_sim(0:age_x, male, jj, ii, yr, sim_ii))
                        
                end do ! End loop over sexes
                
            end do ! End loop over areas

            N_plus_area123(yr, ii, sim_ii) = sum(N_age_sex_area_stock_yr_sim(1:age_x, 1:2, 1:3, ii, yr, sim_ii)) ! yr, stock, sim
            N_tot_area123(yr, ii, sim_ii) = sum(N_age_sex_area_stock_yr_sim(0:age_x, 1:2, 1:3, ii, yr, sim_ii))
            
          end do     ! End loop over stocks 
        
        N_plus_area123(yr, 0, sim_ii) = sum(N_age_sex_area_stock_yr_sim(1:age_x, 1:2, 1:3, 1:n_stocks, yr, sim_ii)) ! yr, stock, sim
        N_tot_area123(yr, 0, sim_ii) = sum(N_age_sex_area_stock_yr_sim(0:age_x, 1:2, 1:3, 1:n_stocks, yr, sim_ii))  ! add abundance across stocks
        
        N_plus(yr) = sum(N_age_sex_area_stock_yr_sim(1:age_x, 1:2, 1:3, 1:n_stocks, yr, sim_ii)) ! Total ages 1+ in survey area (areas 1-3)
        N_tot(yr) = sum(N_age_sex_area_stock_yr_sim(0:age_x, 1:2, 1:3, 1:n_stocks, yr, sim_ii)) ! Total all ages (0+) in survey area (areas 1-3)
        
        is_surv_yr(yr) = mod(yr - 1, surv_freq) ! mod() is intrinsic function for the remainder. If zero, it's a survey year
!        
        if (is_surv_yr(yr) == 0) then
            n_hat_yr_sim(yr, sim_ii) = gen_survey_estimate(true_abundance = N_tot_area123(yr, 0, sim_ii), cv = cv_n) ! Assumes surveys apply to ages 0+ (cf. Wade 1998)
! Calculate N_min, at present this is using the lower 20th percentile of the abundance estimate : TODO make z_score a parameter (not hard coded)        
            N_min_yr_sim(yr, sim_ii) = calc_n_min(n_hat = n_hat_yr_sim(yr, sim_ii), cv = cv_n, z_score = 0.842d0)
! If this is a survey year, calculate PBR
            pbr_yr_sim(yr, sim_ii) = N_min_yr_sim(yr, sim_ii) * 0.5d0 * r_max * F_r(1) ! TODO: Make this more general for Tier System
        else 
            pbr_yr_sim(yr, sim_ii) = pbr_yr_sim(yr - 1, sim_ii)
        end if
!        
        sigma_pbr_yr_sim(yr, sim_ii) = cv_mortality(1) * pbr_yr_sim(yr, sim_ii) ! Transform CV for uncertainty in human caused mortality to SD

! Generate normal random deviate with PBR as expectation of human caused mortality        
        M_yr_sim(yr, sim_ii) = random_normal(mean = real(pbr_yr_sim(yr, sim_ii),  4), & ! Need to convert from 8 to 4 bytes w real() : TODO modify random_normal() to 8 byte
          sd = real(sigma_pbr_yr_sim(yr, sim_ii), 4)) 
          
        if (M_yr_sim(yr, sim_ii) < 0.0d0) then ! If populations reach low numbers, negative mortality (i.e. zombies) possible. Alert user.
            print *, "Negative mortality!: ", "yr: ", yr, "sim_ii: ", sim_ii, "M_yr_sim(yr, sim_ii): ", M_yr_sim(yr, sim_ii)
            print *, "Resetting human cause mortality to zero."
            M_yr_sim(yr, sim_ii) = 0.0d0
        end if

! DEBUGGING        
        if(sim_ii == 0) print *, "Year: ", yr, "pbr_yr_sim(yr, sim_ii): ", pbr_yr_sim(yr, sim_ii), &
          "M_yr_sim(yr, sim_ii): ", M_yr_sim(yr, sim_ii), &
          "N_min_yr_sim(yr, sim_ii): ", N_min_yr_sim(yr, sim_ii)
!       
        ! TODO : SUBTRACT PBR FROM STOCKS TODO TODO TODO TODO TODO TODO TODO TODO TODO TODO TODO TODO TODO TODO 
        
      end do        ! End loop over years
      print *, "Finished Simulation: ", sim_ii
    end do          ! End loop over number of simulations
!====== +++ === === +++ === === +++ ===    
! DEBUGGING: Collapse main array as intermediate step towards subtracting human caused mortality
    print *, "Finished main loop"

    print *, "N_tot_sex_area_stock_yr_sim(female, 1:3, 1, 0, 0): ", N_tot_sex_area_stock_yr_sim(female, 1:3, 1, 0, 0)    
    print *, "N_tot_sex_area_stock_yr_sim(male, 1:3, 1, 0, 0): ", N_tot_sex_area_stock_yr_sim(male, 1:3, 1, 0, 0)    
    print *, 
    print *, "pbr_yr_sim(yr = 1, sim_ii = 0): ", pbr_yr_sim(1, 0)
!    Call allocate_pbr(N_tot_area123(yr, 1:3, sim_ii), pbr_yr_sim(yr, sim_ii))
!====== +++ === === +++ === === +++ ===        
!====== +++ === === +++ === === +++ ===    
! DEBUGGING: DEPLETION 
!  Look at calculated depletion through time -- ideally want this written to file for plotting in R etc.
!  Even more ideal(?? or not): write depletion (in its own column) to same file as N_array.out (see below)
!====== +++ === === +++ === === +++ === 
!    print *, "Depletion_yr  : "
!    do yr = 0, yr_max
!        print *, (depl_yr_stock(yr, ii), ii = 1, n_stocks)
!    end do 
!====== +++ === === +++ === === +++ ===    
! Writing results of age aggregated abundance arrays with totals across the survey areas (1,2 and 3) to output file 
!====== +++ === === +++ === === +++ === TODO: Move this into a function in the File IO module       
    open(unit = 2, file = "N_aggregated.out")
    write(2, "(6(a15))") "sim", "yr", "stock", "N_tot_area123", "N_plus_area123", "n_hat_yr"
20  format(3(i15), 3(f15.4)) !       
    do sim_ii = 0, n_sims
      do yr = 0, yr_max
        do ii = 0, n_stocks
          write(2, 20) sim_ii, yr, ii, N_tot_area123(yr, ii, sim_ii), N_plus_area123(yr, ii, sim_ii), n_hat_yr_sim(yr, sim_ii)   
        end do
      end do
    end do
!====== +++ === === +++ === === +++ ===    
! Writing results of major array with spatial-temporal age structure to output file 
! Also writing results of summing over ages in major array (i.e. the slightly smaller array that is pertinent to PBR_calcs)    
!====== +++ === === +++ === === +++ === TODO: Move this into a function in the File IO module       
    open(unit = 3, file = "N_array.out")
    open(unit = 4, file = "N_tot_sex_area_stock_yr_sim.out")    
    write(3, "(13(a15))") "sim", "yr", "stock", "age", "sex", "all_areas", "area_1", "area_2", "area_3", "area_4", &
        "N_plus_area123", "N_tot_area123", "n_hat_yr"  
    write(4, "(8(a15))") "sim", "yr", "stock", "sex", "area1", "area2", "area3", "area4"
30  format(5(i15), 5(f15.4)) ! 
40  format(4(i15), 5(f15.4))
    do sim_ii = 0, n_sims
      do yr = 0, yr_max
        do ii = 1, n_stocks
            do ss = 1, 2
                do aa = 0, age_x ! Note the implicit do loop over areas in next line -- and advance = 'no' for suppressing new line 
                    
                  write(3, 30,  advance='no') sim_ii, yr, ii, aa, ss, (N_age_sex_area_stock_yr_sim( aa , ss, jj , ii, yr, sim_ii), &
                    jj = 0, n_area)
                    
                  write(3, "(3(f15.4))") N_plus_area123(yr, ii, sim_ii), N_tot_area123(yr, ii, sim_ii), n_hat_yr_sim(yr, sim_ii)
                  
                  write(4, 40) sim_ii, yr, ii, ss, (N_age_sex_area_stock_yr_sim( aa , ss, jj , ii, yr, sim_ii), &
                    jj = 1, n_area)
!                  write(4, "(5(f15.4))") (N_tot_sex_area_stock_yr_sim(ss, jj, ii, 0, sim_ii), jj = 1, n_area) 
                    
                end do  ! End ouput for this age
            end do ! End ouput for this sex
        end do ! End output this stock
      end do ! End ouput for this year
    end do ! End output for this simulation
    !write (1, "(A7,I3)") "hello", 10    ! example of conversion and concantination of character string in fortran    
    close(unit = 3) ! close output file
!====== +++ === === +++ === === +++ ===        
! DEVELOPING
! Test some random number generation
!   open(unit = 1, file = "z_variate.out")
!    write(1, format2) "draw_ID", "z_variate"
!    write(*,*) 'z_variates from random_normal()'
!    do jj = 1, 100
!!            z_variate = random_normal(mean = real(S_adult, kind = 4), sd = real(S_juv, kind = 4)) ! Function located in Random_module.f90
!        z_variate = random_normal(mean = 2., sd = 4.) ! Function located in Random_module.f90
!        write(1, format4) jj, z_variate  ! "format4" declared in file = Format_module.f90
!       if (jj .eq. 1) print *, jj, z_variate
!    end do
! END DEVELOPING    
!====== +++ === === +++ === === +++ ===     
    
!$         print *, "Compiled with -fopenmp"    ! This is a test for compiling with OpenMP (parallel processor directive <- !$)
         
    print *, "Closing down"
    return     
!====== +++ === === +++ === === +++ ===   
!###### +++ ### ### +++ ### ### +++ ###             
    contains
!====== +++ === === +++ === === +++ ===   
!###### +++ ### ### +++ ### ### +++ ###             
    subroutine initialize_local_vars()
        print *, "Hello from initialize_local_vars()"
        f_init_ii = 0.d0
        f_yr_stock = 0.d0
        b_init_ii = 0.d0
        b_yr_stock = 0.d0
        depl_yr_stock = 0.d0
        transition_matrix_tmp = 0.d0
        movement_matrix = 0.d0
        N_age_sex_area_stock_yr_sim = 0.d0
        area_stock_prop = 0.d0
        eigv = 0.d0
        n_hat_yr_sim = 0.0d0
        is_surv_yr = 0
        pbr_yr_sim = 0.d0
        foo_vector = 0.d0 
        NPR_mature = 0.d0 
        NPR_age = 0.0d0
        NPR_oneplus = 0.0d0

        foo = 0.d0 
        foo1 = 0.d0  
        objf_lambda = 0.d0 
        objf_f_init = 0.d0 
        lambda = 0.d0 
        io_error = 0
        ii = 0
        jj = 0
        aa = 0
        ss = 0
        yr = 0
        print *, "Goodbye from initialize_local_vars()"
        !
        return
    end subroutine initialize_local_vars

end program main

