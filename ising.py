import numpy as np
import matplotlib.pyplot as plt
import random

H=[]
def read_graph(file_path):
    graph = {}
    num_spins = 0
    with open(file_path, "r") as file:
        lines = file.readlines()
        num_spins = int(lines[0].split()[0])  # 获取节点数量（假设是图的节点数）
        for line in lines[1:]:  # 跳过第一行，读取边数据
            u, v, weight = map(int, line.split())
            if u not in graph:
                graph[u] = []
            if v not in graph:
                graph[v] = []
            graph[u].append((v, weight))
            graph[v].append((u, weight))  # 无向图，双向边
    return graph, num_spins

class MomentumAnnealerRef:
    def __init__(self, J, lambda_max):
        self.N = J.shape[0]
        self.J = np.array(J, dtype=float)
        self.Fl=np.zeros(self.N, dtype=np.float64)
        self.Fr=np.zeros(self.N, dtype=np.float64)
        self.spins_L = np.random.choice([-1,1],size=self.N)
        self.spins_R = np.random.choice([-1,1],size=self.N)
        self.w=np.zeros(self.N,dtype=np.float64)
        for i in range(1,self.N):
            for j in range(1,self.N):
                #self.Fl[i]+=self.J[i][j]*self.spins_R[j]
                #self.Fr[i]+=self.J[i][j]*self.spins_L[j]
                if(self.spins_L[i]==1):
                    if(self.spins_L[j]==1):
                        self.w[i]+=abs(self.J[i][j])-0.5*abs(self.J[i][j])
                    else:
                        self.w[i]+=abs(self.J[i][j])
                else: 
                    self.w[i]=0.5*lambda_max
        self.fs=np.zeros(self.N,dtype=int)    
        self.index=np.zeros(self.N,dtype=int)    
    def energy(self, spins):
        """Ising Hamiltonian energy"""
        return -0.5*(spins @ self.J @ spins)
    
    def update_spin(self,i,T,rand,lr,lf):
        if(lr=='l'): 
            deltaH=2*self.spins_L[i]*lf
        else: 
            deltaH=2*self.spins_R[i]*lf
        #print(deltaH,lf)
        if(deltaH<=0 or  deltaH<=T*rand):
            self.fsn+=1
            if(lr=='l'): 
                self.spins_L[i]=-self.spins_L[i]
                self.fs[self.fsn]=self.spins_L[i]
            else: 
                self.spins_R[i]=-self.spins_R[i]
                self.fs[self.fsn]=self.spins_R[i]
            self.index[self.fsn]=i
    def run(self, steps, T_start, pk_start, momentum_alpha):
        # 初始化自旋 & 动量  
        fs_r_new=[]
        fs_l_new=[]
        fs_indexl_new=[]
        fs_indexr_new=[]  
        Fleft_new=0
        Fright_new=0 
        self.fsn=0   
        for t in range(1,steps+1):
            # 温度调度
            if(t==1):
                Fleft=self.N-1
                Fright=self.N-1
                fs_indexl=[i for i in range(0,self.N)]
                fs_indexr=[i for i in range(0,self.N)]
                fs_r=self.spins_R.copy()
                fs_l=self.spins_L.copy()
            else:
                Fleft=Fleft_new
                Fright=Fright_new
                fs_indexl=fs_indexl_new
                fs_indexr=fs_indexr_new
                fs_r=fs_r_new
                fs_l=fs_l_new
            
            T = T_start * (momentum_alpha**t)
            pk= pk_start-t*1.0/2000
            ck= np.sqrt(t*1.0/1000)
            momentum=np.zeros(self.N)
            
            for i in range(1,self.N):
                rand=np.random.random()
                momentum[i]=(pk<rand)*ck*self.w[i]
                if(Fright==0): 
                    lf=self.Fl[i]+momentum[i]*self.spins_R[i]
                    self.update_spin(i,T,rand,'l',lf)
            
            for i in range(1,Fright+1):
                for j in range (1,self.N):
                    idx=fs_indexr[i]
                    self.Fl[j]+=2*self.J[j][idx]*fs_r[i] if t>1 else self.J[j][idx]*fs_r[i]
                    if(i==Fright):
                        lf=self.Fl[j]+momentum[j]*self.spins_R[j]
                        rand=np.random.random()
                        self.update_spin(j,T,rand,'l',lf)
           # for i in range(1, self.N):
           #     ref = sum(self.J[i][j] * self.spins_R[j] for j in range(1, self.N))
            fs_l_new=self.fs.copy()
            fs_indexl_new=self.index.copy()
            Fleft_new=self.fsn
            self.fsn=0
            #右侧自旋对称
        
            for i in range(1,self.N):
                rand=np.random.random()
                momentum[i]=(pk<rand)*ck*self.w[i]
                if(Fleft==0):
                    lf=self.Fr[i]+momentum[i]*self.spins_L[i]
                    self.update_spin(i,T,rand,'r',lf)
            #for i in range(1, self.N):
            #    self.Fr[i] = sum(self.J[i][j] * self.spins_L[j] for j in range(1, self.N))
            
            for i in range(1,Fleft+1):
                for j in range (1,self.N):
                    idx=fs_indexl[i]
                    self.Fr[j]+=2*self.J[j][idx]*fs_l[i] if t>1 else self.J[j][idx]*fs_l[i]
            #Fl_full = self.J.dot(self.spins_R)
            #Fr_full = self.J.dot(self.spins_L)
            #maxdiff_fl = np.max(np.abs(Fl_full - self.Fl))
            #maxdiff_fr = np.max(np.abs(Fr_full - self.Fr))
            #if maxdiff_fr > 1e-8:
            #    print("Propagation mismatch: maxdiff_fl=", "maxdiff_fr=", maxdiff_fr)        
            if(i==Fleft):
                for j in range(1,self.N):
                    lf=self.Fr[j]+momentum[j]*self.spins_L[j]
                    rand=np.random.random()
                    self.update_spin(j,T,rand,'r',lf)   
            fs_r_new=self.fs.copy()
            fs_indexr_new=self.index.copy()
            Fright_new=self.fsn
            self.fsn=0
            a=self.energy(self.spins_L)
            print(t,Fright_new,Fleft_new,a)

            H.append(a)
        return self.spins_L,a

file_path = 'graph.txt'  # 请确保该路径正确
graph, num_spins = read_graph(file_path)
J = np.zeros((num_spins+1, num_spins+1))  # 初始化交互矩阵
for u in graph:
    for v, weight in graph[u]:
        J[u][v] = weight  # 节点编号从1开始，因此减1
        J[v][u] = weight  # 无向图，矩阵是对称的
eigvals = np.linalg.eigvals(-J)
lambda_max = np.max(eigvals.real)
print(lambda_max)
annealer = MomentumAnnealerRef(J,lambda_max)
steps=800
spins, energy = annealer.run(steps=steps, T_start=13, pk_start=0.5, momentum_alpha=0.9969)
print(np.array2string(spins, separator=','))
x=list(range(1, steps + 1))
plt.plot(x,H, linestyle='-', color='b')
plt.show()

