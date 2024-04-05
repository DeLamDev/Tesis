// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;




import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";





// Contrato principal del pool de recursos
contract CrowdfundingPool is Ownable {
    IERC20 public token; // Token que se utiliza para las contribuciones
    uint256 public conteoProyectos;
    uint256 segundosDia = 86400;




    struct Proyecto {
        // Datos de la solicitud de financiamiento
        address solicitante; // La persona que busca financiamiento
        uint256 financiamiento; // Monto solicitado
        uint256 progreso; // Monto recaudado en cierto punto del tiempo
        uint256 fechaLimite; // Fecha límite para conseguir el financiamiento
        bool fondeado; // Marcador de éxito o fracaso del fondeo del proyecto
        string hashPropuesta; // Hash de IPFS para la propuesta del proyecto




        // Datos post-financiamiento exitoso
        address auditor; // Empresa encargada llevar a cabo la debida diligencia sobre el solicitante
        uint256 cuotaAuditor; // Remuneración otorgada al auditor
        mapping(uint256 => Meta) metas; // Control de la forma en que se liberan los recursos otorgados con base en objetivos
        bool suspendido; // Control si contribuyentes deciden suspendender recursos de un proyecto
    }
    
    // Tipo de dato especial para las metas
    struct Meta {
       uint256 financiamientoMeta; // Monto que se desea liberar e.j (10 pesos de los 100 pesos del financiameinto total)
       string objetivo; // Objetivo a cumplir
       uint256 fechaLimite; // Fecha límite para cumplir con la meta establecida
       uint256 ganacia; // Monto retornado a inversionistas (solo aplica en proyectos onerosos)
       string prueba; // Evidencia por parte del proyecto de
       bool completada;
       uint256 fechaCreacion;
       uint256 duracion;
       uint256 conteoVotos;
       uint8 estatus;
    }


    struct PropuestaAuditor {
        uint256 duracion;
        uint256 fechaCreacion;
        address direccion;
        uint256 cuota;
        uint256 conteoVotos;
        uint8 estatus;
    }


    struct PropuestaSuspension {
        uint256 duracion;
        uint256 fechaCreacion;
        uint256 conteoVotos;
        bool decision;
        uint8 estatus;
    }


    struct PropuestaRevision {
        uint256 idMeta;
        uint256 duracion;
        uint256 fechaCreacion;
        uint256 conteoVotos;
        bool decision;
        uint8 estatus;
    }


    struct Boleta {
        PropuestaAuditor auditor;
        Meta[] metas;
        PropuestaSuspension suspension;
        PropuestaRevision revision;
    }




    enum Votacion { Metas, Auditor, Suspension, Revision }




    mapping(uint256 => Proyecto) public proyectos;
    mapping(address => mapping(uint256 => uint256)) public inversionistas;
    mapping(uint256 => Boleta) public boletas;
    mapping (uint256 => string) public objetivos;




    event ProyectoCreado(uint256 indexed id, address indexed creador);
    event InversionHecha(uint256 indexed id, address indexed inversionista, uint256 cantidad);
    event ProyectoFondeado(uint256 indexed idProyecto, address indexed creador);
    event AuditorContratado(uint256 indexed idProyecto, address indexed auditor);





    constructor(address _tokenAddress) {
        token = IERC20(_tokenAddress);
    }




    // Función para que los solicitantes puedan crear proyectos
    // Se les asigna un id único a cada proyecto
    // El solicitante es quien llama la función
    function crearProyecto(uint256 financiamiento, uint256 limite, string memory propuesta) external {
        require(financiamiento > 0, "La cantidad objetivo debe ser mayor que cero");
        require(limite > block.timestamp, "La fecha limite debe estar en el futuro");
        require(bytes(propuesta).length > 0, "La propuesta no puede estar vacia.");


        conteoProyectos++;
        Proyecto storage nuevoProyecto = proyectos[conteoProyectos];
        nuevoProyecto.solicitante = msg.sender;
        nuevoProyecto.financiamiento = financiamiento;
        nuevoProyecto.fechaLimite = limite;
        nuevoProyecto.hashPropuesta = propuesta;


        emit ProyectoCreado(conteoProyectos, msg.sender);
    }




    // Función para que los inversionista puedan aportar a proyectos
    function invertir(uint256 idProyecto, uint256 cantidad) external {
        Proyecto storage proyecto = proyectos[idProyecto];
        require(!proyecto.fondeado, "El proyecto ya ha sido financiado.");
        require(block.timestamp < proyecto.fechaLimite, "La fecha limite para contribuir ha pasado.");
        require(cantidad > 0, "La inversion debe ser mayor a cero.");
        require(cantidad <= (proyecto.financiamiento - proyecto.progreso),"Inversion excede el financiamiento solicitado");
        require(token.balanceOf(msg.sender) >= cantidad, "Balance insuficiente.");


        token.transferFrom(msg.sender, address(this), cantidad);
        proyecto.progreso += cantidad;
        inversionistas[msg.sender][idProyecto].push(cantidad);
        if(proyecto.progreso == proyecto.financiamiento) {
            proyecto.fondeado = true;
        }


        emit InversionHecha(idProyecto, msg.sender, cantidad);
    }




    function someterAVoto(Votacion tipoVotacion, uint256 idProyecto, uint256 duracion, bytes memory datos) external {
        Proyecto proyecto = proyectos[idProyecto];
        require(proyecto.fondeado == true, "El proyecto aun no ha sido financiado en su totalidad.");
        require(datos.lenght > 0, "Se deben presentar los datos a someter a votacion.");
        require(duracion > 0, "La duracion debe ser mayor a cero.");
        if (tipoVotacion == Votacion.Metas) {
            require(msg.sender == proyecto.solicitante, "Solo el solicitante puede proponer metas.");
            uint256[] memory propuesta = abi.decode(datos, (uint256[]));
            require(propuesta.lenght > 0, "Error con los datos enviados de metas.");
            require(proyecto.financiamiento > propuesta[0], "El monto a liberar no puede ser mayor al financiamiento.");
            require(propuesta[1] >= 0 && objetivos[propuesta[1]], "No existe dicha propuesta.");
            require(proyecto.fechaLimite < propuesta[2] && 
            (propuesta[2] + (segundosDia * 7) + duracion) > block.timestamp, 
            "La fecha no puede ser menor a la fecha de financiamiento y la duracion + una semana");
            if (boletas[idProyecto]) {
                Boleta boleta;
                Meta meta;
                meta.financiamientoMeta = propuesta[0];
                meta.objetivo = objetivos[propuesta[1]];
                meta.fechaLimite = propuesta[2];
                meta.fechaCreacion = block.timestamp;
                meta.duracionVotacion = duracion;
                boleta.metas[0] = meta;
                boletas[idProyecto] = boleta;
            } else {
                uint256 num_metas = boletas[idProyecto].metas.length;
                Meta memory meta;
                meta.financiamientoMeta = propuesta[0];
                meta.objetivo = objetivos[propuesta[1]];
                meta.fechaLimite = propuesta[2];
                meta.fechaCreacion = block.timestamp;
                meta.duracionVotacion = duracion;
                boletas[idProyecto].metas[num_metas] = meta;
            }



        } else if (tipoVotacion == Votacion.Auditor) {
            require(msg.sender == proyecto.solicitante, "Solo el solicitante puede proponer al auditor.");
            (address auditor, uint256 cuota, bool isToken) = abi.decode(datos, (address, uint256, bool));
            require(auditor != address(0), "No se puede proponer la direccion cero.");
            if (boletas[idProyecto]) {
                Boleta boleta;
                PropuestaAuditor propuesta_auditor;
                propuesta_auditor.direccion = auditor;
                propuesta_auditor.cuota = cuota;
                propuesta_auditor.duracion = duracion;
                propuesta_auditor.fechaCreacion = block.timestamp;
            } else {
                boletas[idProyecto].auditor.direccion = auditor;
                boletas[idProyecto].auditor.cuota = cuota;
                boletas[idProyecto].auditor.duracion = duracion;
                boletas[idProyecto].auditor.fechaCreacion = block.timestamp;
            }


        } else if (tipoVotacion == Votacion.Suspension) {
            require(inversionistas[msg.sender][idProyecto] > 0, "Debes haber invertido en el proyecto para someter a aprobacion.");
            bool suspender = abi.decode(datos, (bool));
            require(suspender == true || suspender == false, "Tipo de datos incorrecto para el tipo de votacion.");
            votacionesPendientes[idProyecto] = proyectos[idProyecto];
            votacionesPendientes[idProyecto].suspendido = suspender;
            votacionesPendientes[idProyecto].fechaCreacion = block.timestamp;
            votacionesPendientes[idProyecto].duracionVotacion = duracion;




        } else if (tipoVotacion == Votacion.Revision) {
            require(inversionistas[msg.sender][idProyecto] > 0, "Debes haber invertido en el proyecto para someter a aprobacion.");
            uint256[] memory metas = abi.decode(datos, (uint256[]));
            require(metas.lenght > 0, "Error con los datos enviados de metas.");
            votacionesPendientes[idProyecto] = proyectos[idProyecto];
            votacionesPendientes[idProyecto].suspendido = true;
            votacionesPendientes[idProyecto].fechaCreacion = block.timestamp;
            votacionesPendientes[idProyecto].duracionVotacion = duracion;




        }
    }


    function suspender_proyecto(uint256 idProyecto) public {
        require(proyectos[idProyecto], "El proyecto no existe.");
        require(inversionistas[msg.sender][idProyecto] > 0, "Tienes que ser inversionista.");
        require(proyectos[idProyecto].fondeado == true, "Proyecto no fondeado completamente.");
        
    }




    function setAuditor(uint256 _projectId, uint256 _auditorFeeOffer) external {
        Proyecto storage proyecto = proyectos[_projectId];
        require(project.creator != address(0), "El proyecto no existe");
        require(project.auditor == address(0), "El auditor ya esta asignado");
        require(msg.sender != project.creator, "No puedes ser el auditor de tu propio proyecto");
        require(_auditorFeeOffer > 0 && _auditorFeeOffer <= 100, "Tarifa del auditor invalida");





        project.auditor = msg.sender;
        project.auditorFeeOffer = _auditorFeeOffer;




        emit AuditorHired(_projectId, msg.sender);
    }




    function setMilestone(uint256 _projectId, uint256 _goal, uint256 _deadline) external onlyOwner {
        Project storage project = projects[_projectId];
        require(project.creator != address(0), "El proyecto no existe");
        require(_goal > 0, "La meta debe ser mayor que cero");
        require(_deadline > block.timestamp, "La fecha limite debe estar en el futuro");




        project.milestoneGoal = _goal;
        project.milestoneDeadline = _deadline;




        emit MilestoneSet(_projectId, _goal, _deadline);
    }




    function completeMilestone(uint256 _projectId, string memory _proof) external {
        Project storage project = projects[_projectId];
        require(project.creator != address(0), "El proyecto no existe");
        require(msg.sender == project.creator || msg.sender == project.auditor, "Solo el creador o el auditor pueden completar hitos");
        require(!project.milestoneCompleted, "El hito ya esta completo");
        require(block.timestamp < project.milestoneDeadline, "La fecha limite para completar el hito ha pasado");
        require(project.milestoneProgress + msg.value <= project.milestoneGoal, "La cantidad supera la meta del hito");




        project.milestoneProgress += msg.value;
        project.milestoneProof = _proof;
        project.milestoneCompleted = true;




        emit MilestoneCompleted(_projectId, _proof);
    }




    function withdrawProfits(uint256 _projectId) external {
        Project storage project = projects[_projectId];
        require(project.creator != address(0), "El proyecto no existe");
        require(project.funded, "El proyecto no ha sido financiado");
        require(!project.milestoneCompleted, "El proyecto tiene un hito pendiente");
        
        uint256 contributorShare = (project.currentAmount * (100 - auditorFee)) / 100;
        uint256 auditorShare = project.currentAmount - contributorShare;




        if (msg.sender == project.creator) {
            require(block.timestamp > project.deadline, "El plazo de financiamiento aun no ha terminado");
            token.transfer(project.creator, contributorShare + auditorShare);
        } else {
            require(msg.sender != project.auditor, "El auditor no puede retirar fondos hasta que el proyecto este completo");
            require(block.timestamp > project.milestoneDeadline, "El plazo del hito aun no ha terminado");
            token.transfer(msg.sender, contributorShare);
        }




        emit ProfitsWithdrawn(_projectId, msg.sender, contributorShare);
    }




    // Otras funciones de consulta para obtener información del proyecto
    function getProjectDetails(uint256 _projectId) external view returns (
        address creator,
        uint256 goalAmount,
        uint256 currentAmount,
        uint256 deadline,
        bool funded,
        string memory proposalHash,
        address auditor,
        uint256 auditorFeeOffer,
        uint256 milestoneGoal,
        uint256 milestoneDeadline,
        uint256 milestoneProgress,
        string memory milestoneProof,
        bool milestoneCompleted
    ) {
        Project storage project = projects[_projectId];
        return (
            project.creator,
            project.goalAmount,
            project.currentAmount,
            project.deadline,
            project.funded,
            project.proposalHash,
            project.auditor,
            project.auditorFeeOffer,
            project.milestoneGoal,
            project.milestoneDeadline,
            project.milestoneProgress,
            project.milestoneProof,
            project.milestoneCompleted
        );
    }




    function getContributorProjects(address _contributor) external view returns (uint256[] memory) {
        return contributorProjects[_contributor];
    }
}
